import Foundation

/// A tiny 8-bit synthesiser: square, triangle and noise voices turned into sound effects and music loops, all as plain arrays of samples
/// (mono, 44.1 kHz, -1...1). It does no playing, so it can be tested: every sound must be finite, within range, audible and the right length.
/// The music lives in `ChipMusic.swift`.
enum ChipSynth {
    static let sampleRate = 44_100.0

    // MARK: Voices

    enum Wave { case square(duty: Double), triangle, sine }

    struct Noise {
        var state: UInt32 = 0x1234_ABCD
        mutating func next() -> Float {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            return Float(Int32(bitPattern: state)) / Float(Int32.max)
        }
    }

    static func wave(_ shape: Wave, _ phase: Double) -> Float {
        let p = phase - phase.rounded(.down)
        switch shape {
        case .square(let duty): return p < duty ? 1 : -1
        case .triangle: return Float(4 * abs(p - 0.5) - 1)
        case .sine: return Float(sin(2 * Double.pi * p))
        }
    }

    static func frequency(_ note: Int) -> Double { 440 * pow(2, Double(note - 69) / 12) }

    static func count(_ seconds: Double) -> Int { max(1, Int((seconds * sampleRate).rounded())) }

    /// Adds a note: a short attack, then a decay that reaches silence at the end of the note.
    static func note(_ buffer: inout [Float], at start: Int, seconds: Double, from f0: Double, to f1: Double? = nil, _ shape: Wave, volume: Float,
                     attack: Double = 0.004, curve: Double = 1.4, vibrato: Double = 0) {
        let length = count(seconds)
        var phase = 0.0
        for i in 0..<length {
            let index = start + i
            guard index >= 0, index < buffer.count else { continue }
            let t = Double(i) / Double(length)
            var f = f0 + ((f1 ?? f0) - f0) * t
            if vibrato > 0 { f *= 1 + vibrato * sin(2 * Double.pi * 5.5 * Double(i) / sampleRate) }
            phase += f / sampleRate
            let up = min(1, Double(i) / (attack * sampleRate))
            let env = Float(up * pow(1 - t, curve))
            buffer[index] += wave(shape, phase) * env * volume
        }
    }

    /// A burst of noise with an exponential decay (`tau` seconds), optionally smoothed (low-pass) so it sounds duller.
    static func noiseBurst(_ buffer: inout [Float], at start: Int, seconds: Double, tau: Double, volume: Float, smooth: Int = 1, highpass: Bool = false) {
        var rng = Noise(state: 0x9E37_79B9 &+ UInt32(truncatingIfNeeded: start))
        let length = count(seconds)
        var window = [Float](repeating: 0, count: max(1, smooth))
        var sum: Float = 0
        var previous: Float = 0, filtered: Float = 0
        for i in 0..<length {
            let index = start + i
            guard index >= 0, index < buffer.count else { continue }
            var sample = rng.next()
            if smooth > 1 {
                let slot = i % smooth
                sum += sample - window[slot]; window[slot] = sample
                sample = sum / Float(smooth) * 2.2
            }
            if highpass { filtered = 0.9 * (filtered + sample - previous); previous = sample; sample = filtered }
            let env = Float(exp(-Double(i) / sampleRate / tau))
            let fade = Float(min(1, Double(length - i) / (0.01 * sampleRate)))
            buffer[index] += sample * env * fade * volume
        }
    }

    /// Scales the buffer down if it would clip, so nothing is louder than `ceiling`.
    static func finish(_ buffer: [Float], ceiling: Float = 0.92) -> [Float] {
        let peak = buffer.map { abs($0) }.max() ?? 0
        guard peak > 0 else { return buffer }
        let scale = min(1, ceiling / peak)
        return buffer.map { max(-1, min(1, $0 * scale)) }
    }

    // MARK: Effects

    static func render(_ effect: SoundEffect) -> [Float] {
        switch effect {
        case .tap:
            var b = [Float](repeating: 0, count: count(0.06))
            note(&b, at: 0, seconds: 0.06, from: 880, to: 1320, .square(duty: 0.5), volume: 0.4)
            return finish(b)
        case .coin:
            var b = [Float](repeating: 0, count: count(0.36))
            note(&b, at: 0, seconds: 0.07, from: frequency(83), .square(duty: 0.5), volume: 0.35)
            note(&b, at: count(0.07), seconds: 0.27, from: frequency(88), .square(duty: 0.5), volume: 0.35, curve: 1.8)
            return finish(b)
        case .denied:
            var b = [Float](repeating: 0, count: count(0.36))
            note(&b, at: 0, seconds: 0.11, from: 220, .square(duty: 0.5), volume: 0.4)
            note(&b, at: count(0.13), seconds: 0.22, from: 165, .square(duty: 0.5), volume: 0.4)
            return finish(b)
        case .notice:
            var b = [Float](repeating: 0, count: count(0.4))
            note(&b, at: 0, seconds: 0.12, from: frequency(76), .triangle, volume: 0.6)
            note(&b, at: count(0.12), seconds: 0.28, from: frequency(81), .triangle, volume: 0.6, curve: 1.6)
            return finish(b)
        case .alarm:
            var b = [Float](repeating: 0, count: count(0.74))
            for i in 0..<6 { note(&b, at: count(0.12) * i, seconds: 0.11, from: i % 2 == 0 ? 784 : 622, .square(duty: 0.5), volume: 0.38, curve: 0.6) }
            return finish(b)
        case .arrival:
            var b = [Float](repeating: 0, count: count(0.7))
            noiseBurst(&b, at: 0, seconds: 0.28, tau: 0.12, volume: 0.22, smooth: 7)
            for (i, n) in [60, 64, 67, 72].enumerated() { note(&b, at: count(0.1) + count(0.08) * i, seconds: i == 3 ? 0.3 : 0.12, from: frequency(n), .triangle, volume: 0.6) }
            return finish(b)
        case .routeOpened:
            var b = [Float](repeating: 0, count: count(0.5))
            for (i, n) in [72, 76, 79, 84].enumerated() { note(&b, at: count(0.08) * i, seconds: i == 3 ? 0.2 : 0.1, from: frequency(n), .square(duty: 0.25), volume: 0.35) }
            return finish(b)
        case .levelUp:
            var b = [Float](repeating: 0, count: count(0.72))
            for (i, n) in [76, 79, 83, 88, 91].enumerated() {
                note(&b, at: count(0.075) * i, seconds: i == 4 ? 0.3 : 0.12, from: frequency(n), .square(duty: 0.25), volume: 0.28)
                note(&b, at: count(0.075) * i, seconds: i == 4 ? 0.3 : 0.12, from: frequency(n - 12), .triangle, volume: 0.3)
            }
            return finish(b)
        case .gameOver:
            var b = [Float](repeating: 0, count: count(1.5))
            for (i, n) in [67, 63, 60, 55].enumerated() {
                note(&b, at: count(0.22) * i, seconds: i == 3 ? 0.7 : 0.24, from: frequency(n), .square(duty: 0.5), volume: 0.3, curve: 1.0)
                note(&b, at: count(0.22) * i, seconds: i == 3 ? 0.7 : 0.24, from: frequency(n - 12), .triangle, volume: 0.35, curve: 1.0)
            }
            return finish(b)
        }
    }
}
