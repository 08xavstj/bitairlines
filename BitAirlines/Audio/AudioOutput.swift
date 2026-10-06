import Foundation
import AVFoundation

/// Where sound actually comes out. The game talks to this protocol, so tests and screenshot runs can use a silent one.
@MainActor
protocol AudioOutput: AnyObject {
    /// Gets the audio system ready. False if it could not (no output, or another app owns it): the game then stays silent.
    func start() -> Bool
    func suspend()
    func play(_ effect: SoundEffect, samples: [Float], volume: Float)
    func playMusic(_ theme: MusicTheme, samples: [Float], volume: Float)
    func setMusicVolume(_ volume: Float)
    func stopMusic()
}

/// Plays nothing, and remembers what it was asked to play (tests, previews, screenshot runs).
@MainActor
final class SilentAudioOutput: AudioOutput {
    private(set) var effects: [SoundEffect] = []
    private(set) var music: MusicTheme?
    private(set) var musicVolume: Float = 0
    func start() -> Bool { true }
    func suspend() {}
    func play(_ effect: SoundEffect, samples: [Float], volume: Float) { effects.append(effect) }
    func playMusic(_ theme: MusicTheme, samples: [Float], volume: Float) { music = theme; musicVolume = volume }
    func setMusicVolume(_ volume: Float) { musicVolume = volume }
    func stopMusic() { music = nil }
}

/// The real thing: an AVAudioEngine with one looping music player and a few effect players. The "ambient" session category follows the silent
/// switch and lets other apps' audio carry on, which is what a game that is not the main event should do.
@MainActor
final class SystemAudioOutput: AudioOutput {
    private let engine = AVAudioEngine()
    private let musicNode = AVAudioPlayerNode()
    private var effectNodes: [AVAudioPlayerNode] = []
    private var nextEffectNode = 0
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: ChipSynth.sampleRate, channels: 1, interleaved: false)!
    private var effectBuffers: [SoundEffect: AVAudioPCMBuffer] = [:]
    private var musicBuffers: [MusicTheme: AVAudioPCMBuffer] = [:]
    private var wantedMusic: (theme: MusicTheme, volume: Float)?
    private var observers: [NSObjectProtocol] = []
    private var running = false

    init() {
        engine.attach(musicNode)
        engine.connect(musicNode, to: engine.mainMixerNode, format: format)
        for _ in 0..<6 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            effectNodes.append(node)
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                guard let self else { return }
                if raw == AVAudioSession.InterruptionType.ended.rawValue { _ = self.start(); self.resumeMusic() } else { self.running = false }
            }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { guard let self else { return }; self.running = false; if self.start() { self.resumeMusic() } }
        })
    }

    // The output lives as long as the app does, so its notification observers are never removed.

    func start() -> Bool {
        if running, engine.isRunning { return true }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            running = true
        } catch { running = false }
        return running
    }

    func suspend() {
        musicNode.pause()
        engine.pause()
        running = false
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)), let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    func play(_ effect: SoundEffect, samples: [Float], volume: Float) {
        guard start() else { return }
        let pcm: AVAudioPCMBuffer
        if let cached = effectBuffers[effect] { pcm = cached } else if let made = buffer(samples) { effectBuffers[effect] = made; pcm = made } else { return }
        let node = effectNodes[nextEffectNode]
        nextEffectNode = (nextEffectNode + 1) % effectNodes.count
        node.volume = volume
        node.scheduleBuffer(pcm, at: nil, options: .interrupts)
        if !node.isPlaying { node.play() }
    }

    func playMusic(_ theme: MusicTheme, samples: [Float], volume: Float) {
        wantedMusic = (theme, volume)
        guard start() else { return }
        let pcm: AVAudioPCMBuffer
        if let cached = musicBuffers[theme] { pcm = cached } else if let made = buffer(samples) { musicBuffers[theme] = made; pcm = made } else { return }
        musicNode.stop()
        musicNode.volume = volume
        musicNode.scheduleBuffer(pcm, at: nil, options: .loops)
        musicNode.play()
    }

    private func resumeMusic() {
        guard let wanted = wantedMusic, let pcm = musicBuffers[wanted.theme] else { return }
        musicNode.stop()
        musicNode.volume = wanted.volume
        musicNode.scheduleBuffer(pcm, at: nil, options: .loops)
        musicNode.play()
    }

    func setMusicVolume(_ volume: Float) {
        musicNode.volume = volume
        if let wanted = wantedMusic { wantedMusic = (wanted.theme, volume) }
    }

    func stopMusic() {
        wantedMusic = nil
        musicNode.stop()
    }
}
