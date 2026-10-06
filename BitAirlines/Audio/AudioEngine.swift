import SwiftUI
import Observation

/// The game's sound and music. Screens ask for a sound or a theme; this obeys the player's settings (effects on or off, music on or off, volume).
@MainActor
@Observable
final class AudioEngine {
    @ObservationIgnored private let output: AudioOutput
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var effectSamples: [SoundEffect: [Float]] = [:]
    @ObservationIgnored private var musicSamples: [MusicTheme: [Float]] = [:]
    @ObservationIgnored private var rendering: Set<MusicTheme> = []
    /// The theme that should be playing (even while music is switched off, so it starts when it is switched on).
    private(set) var theme: MusicTheme?
    @ObservationIgnored private var playing: MusicTheme?
    @ObservationIgnored private var suspended = false
    /// Builds a music loop. The real synth takes a moment; tests pass a quick stand-in.
    @ObservationIgnored private let renderMusic: @Sendable (MusicTheme) -> [Float]

    init(output: AudioOutput, settings: AppSettings, renderMusic: @escaping @Sendable (MusicTheme) -> [Float] = { ChipSynth.render($0) }) {
        self.output = output
        self.settings = settings
        self.renderMusic = renderMusic
        settings.onChange = { [weak self] in self?.refreshMusic() }
    }

    /// The real output on a phone; a silent one in tests and in screenshot runs, which have no speakers to use.
    static func makeOutput() -> AudioOutput {
        #if DEBUG
        if Demo.screen != nil { return SilentAudioOutput() }
        #endif
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return SilentAudioOutput() }
        return SystemAudioOutput()
    }

    private var volume: Float { Float(settings.volume.gain) }

    func play(_ effect: SoundEffect) {
        guard settings.soundEffects, !suspended, volume > 0 else { return }
        let samples: [Float]
        if let cached = effectSamples[effect] { samples = cached } else { samples = ChipSynth.render(effect); effectSamples[effect] = samples }
        output.play(effect, samples: samples, volume: effect.gain * volume)
    }

    /// Plays the most important of several sounds that happened together.
    func play(strongest effects: [SoundEffect]) {
        if let best = effects.max(by: { $0.priority < $1.priority }) { play(best) }
    }

    /// Chooses the background music (nil for none). The loop is built off the main thread the first time it is needed.
    func setMusic(_ theme: MusicTheme?) {
        self.theme = theme
        refreshMusic()
    }

    /// Call after a setting changes.
    func refreshMusic() {
        guard let theme, settings.music, !suspended, volume > 0 else {
            if playing != nil { output.stopMusic(); playing = nil }
            return
        }
        if playing == theme { output.setMusicVolume(theme.gain * volume); return }
        if let samples = musicSamples[theme] {
            output.playMusic(theme, samples: samples, volume: theme.gain * volume)
            playing = theme
        } else if !rendering.contains(theme) {
            rendering.insert(theme)
            let render = renderMusic
            Task { [weak self] in
                let samples = await Task.detached(priority: .utility) { render(theme) }.value
                guard let self else { return }
                self.rendering.remove(theme)
                self.musicSamples[theme] = samples
                if self.theme == theme { self.refreshMusic() }
            }
        }
    }

    /// The app has gone to the background (or come back).
    func setSuspended(_ value: Bool) {
        guard value != suspended else { return }
        suspended = value
        if value { output.stopMusic(); playing = nil; output.suspend() } else { refreshMusic() }
    }
}

// MARK: - In the view tree

private struct AudioKey: EnvironmentKey {
    static let defaultValue: AudioEngine? = nil
}

extension EnvironmentValues {
    /// The game's sound, or nil in a preview or test that has none.
    var audio: AudioEngine? {
        get { self[AudioKey.self] }
        set { self[AudioKey.self] = newValue }
    }
}

/// A button look that is just the label, with a tap sound when it is pressed.
struct TapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.pressSound(configuration.isPressed)
    }
}

extension ButtonStyle where Self == TapButtonStyle {
    static var tap: TapButtonStyle { TapButtonStyle() }
}

extension View {
    /// Plays the tap sound when `pressed` turns true. Used by every button style so each press is heard.
    func pressSound(_ pressed: Bool) -> some View { modifier(PressSound(pressed: pressed)) }
}

private struct PressSound: ViewModifier {
    let pressed: Bool
    @Environment(\.audio) private var audio

    func body(content: Content) -> some View {
        content.onChange(of: pressed) { _, now in if now { audio?.play(.tap) } }
    }
}
