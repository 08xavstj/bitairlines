import Foundation

/// The two music loops, built from the chip voices in `ChipSynth`. Each is eight bars of eight steps, written as plain data.
extension ChipSynth {
    /// One loop of music: a bass line, an arpeggio, a lead, and drums. Notes are MIDI numbers per eighth-note step; 0 is a rest.
    struct Song {
        var bpm: Double
        /// Chords, one per bar of eight steps.
        var chords: [[Int]]
        var bassRoots: [Int]
        /// Offsets from the root per step, with -99 for a rest.
        var bassPattern: [Int]
        /// Index into the chord per step, with -1 for a rest.
        var arpPattern: [Int]
        var arpOctave: Int
        /// Per bar: (note, steps) pairs that add up to eight steps; note 0 is a rest.
        var lead: [[(Int, Int)]]
        var kick: Set<Int>, snare: Set<Int>
        var hats: Bool
        var leadShape: Wave
        var bassShape: Wave
        var arpDuty: Double
        var levels: (bass: Float, arp: Float, lead: Float, drums: Float)

        var steps: Int { chords.count * 8 }
    }

    static func song(for theme: MusicTheme) -> Song {
        switch theme {
        case .title:
            // D minor, a little restless: Dm Bb Gm A, then Dm Bb F A.
            let dm = [50, 53, 57], bb = [46, 50, 53], gm = [43, 46, 50], a = [45, 49, 52], f = [53, 57, 60]
            return Song(bpm: 96, chords: [dm, bb, gm, a, dm, bb, f, a], bassRoots: [38, 34, 43, 45, 38, 34, 41, 45],
                        bassPattern: [0, -99, 0, -99, 12, -99, 0, -99], arpPattern: [0, 1, 2, 1, 0, 1, 2, 1], arpOctave: 12,
                        lead: [[(74, 3), (72, 1), (69, 2), (65, 2)], [(70, 3), (72, 1), (74, 4)], [(67, 2), (70, 2), (74, 2), (70, 2)], [(69, 4), (73, 2), (76, 2)],
                               [(77, 3), (76, 1), (74, 2), (72, 2)], [(70, 4), (72, 2), (70, 2)], [(69, 2), (72, 2), (77, 4)], [(76, 6), (0, 2)]],
                        kick: [0, 4], snare: [], hats: true, leadShape: .square(duty: 0.5), bassShape: .triangle, arpDuty: 0.25, levels: (0.5, 0.2, 0.28, 0.18))
        case .flying:
            // G major and slow, for long flights: G Em C D, then G Em Am D. The melody leaves the first two bars empty.
            let g = [55, 59, 62], em = [52, 55, 59], c = [48, 52, 55], d = [50, 54, 57], am = [57, 60, 64]
            return Song(bpm: 72, chords: [g, em, c, d, g, em, am, d], bassRoots: [43, 40, 48, 38, 43, 40, 45, 38],
                        bassPattern: [0, -99, -99, -99, 7, -99, -99, -99], arpPattern: [0, -1, 1, -1, 2, -1, 1, -1], arpOctave: 12,
                        lead: [[(0, 8)], [(0, 8)], [(76, 4), (74, 2), (72, 2)], [(74, 6), (0, 2)], [(79, 4), (76, 2), (74, 2)], [(71, 4), (74, 2), (76, 2)],
                               [(72, 2), (76, 2), (81, 4)], [(78, 4), (74, 2), (0, 2)]],
                        kick: [], snare: [], hats: false, leadShape: .triangle, bassShape: .triangle, arpDuty: 0.125, levels: (0.45, 0.14, 0.25, 0))
        }
    }

    /// Seconds one loop of the theme lasts.
    static func loopSeconds(_ theme: MusicTheme) -> Double {
        let s = song(for: theme)
        return Double(s.steps) * 60 / s.bpm / 2
    }

    /// A seamless loop of the theme (the last samples fade into the first, with no click).
    static func render(_ theme: MusicTheme) -> [Float] {
        let s = song(for: theme)
        let step = 60 / s.bpm / 2
        let stepSamples = count(step)
        var buffer = [Float](repeating: 0, count: stepSamples * s.steps + count(0.6))        // a tail that wraps round to the start
        for bar in 0..<s.chords.count {
            let chord = s.chords[bar]
            for i in 0..<8 {
                let start = (bar * 8 + i) * stepSamples
                let offset = s.bassPattern[i]
                if offset != -99 { note(&buffer, at: start, seconds: step * 1.8, from: frequency(s.bassRoots[bar] + offset), s.bassShape, volume: s.levels.bass, curve: 0.8) }
                let arp = s.arpPattern[i]
                if arp >= 0 { note(&buffer, at: start, seconds: step * 1.3, from: frequency(chord[arp] + s.arpOctave), .square(duty: s.arpDuty), volume: s.levels.arp, curve: 1.6) }
                if s.kick.contains(i) { note(&buffer, at: start, seconds: 0.16, from: 130, to: 45, .sine, volume: s.levels.drums * 1.6, attack: 0.001, curve: 1.3) }
                if s.snare.contains(i) { noiseBurst(&buffer, at: start, seconds: 0.14, tau: 0.04, volume: s.levels.drums * 0.9, smooth: 2) }
                if s.hats { noiseBurst(&buffer, at: start, seconds: 0.04, tau: 0.01, volume: s.levels.drums * (i % 2 == 0 ? 0.3 : 0.18), smooth: 1, highpass: true) }
            }
            var position = 0
            for (n, steps) in s.lead[bar] {
                if n != 0 {
                    note(&buffer, at: (bar * 8 + position) * stepSamples, seconds: step * Double(steps) * 0.95, from: frequency(n), s.leadShape, volume: s.levels.lead, curve: 0.7,
                         vibrato: steps >= 3 ? 0.008 : 0)
                }
                position += steps
            }
        }
        // Fold the tail back onto the start so the loop is seamless.
        let loop = stepSamples * s.steps
        var out = Array(buffer[0..<loop])
        for i in 0..<(buffer.count - loop) { out[i] += buffer[loop + i] }
        return finish(out, ceiling: 0.8)
    }
}
