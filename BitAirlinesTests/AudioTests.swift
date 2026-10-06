import Testing
import Foundation
import CoreCatalog
import CoreWorld
@testable import BitAirlines

@Suite struct ChipSynthTests {
    @Test func everyEffectIsAudibleAndInRange() {
        for effect in SoundEffect.allCases {
            let samples = ChipSynth.render(effect)
            let peak = samples.map { abs($0) }.max() ?? 0
            let seconds = Double(samples.count) / ChipSynth.sampleRate
            #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 1 }, "\(effect.rawValue) has bad samples")
            #expect(peak > 0.2, "\(effect.rawValue) is too quiet")
            #expect(seconds > 0.03 && seconds < 2.0, "\(effect.rawValue) lasts \(seconds) seconds")
            #expect(effect.gain > 0 && effect.gain <= 1)
        }
    }

    @Test func everyEffectHasItsOwnPriority() {
        let priorities = SoundEffect.allCases.map(\.priority)
        #expect(Set(priorities).count == priorities.count)
    }

    @Test func songsAreWrittenCorrectly() {
        for theme in MusicTheme.allCases {
            let song = ChipSynth.song(for: theme)
            #expect(song.chords.count == 8 && song.bassRoots.count == 8 && song.lead.count == 8, "\(theme.rawValue) needs eight bars")
            #expect(song.bassPattern.count == 8 && song.arpPattern.count == 8)
            for (bar, notes) in song.lead.enumerated() { #expect(notes.map(\.1).reduce(0, +) == 8, "\(theme.rawValue) bar \(bar + 1) does not add up to eight steps") }
            for chord in song.chords { #expect(chord.count == 3) }
            #expect(song.arpPattern.allSatisfy { $0 < 3 })
        }
    }

    @Test func musicLoopsHaveTheRightLengthAndAreAudible() {
        for theme in MusicTheme.allCases {
            let samples = ChipSynth.render(theme)
            let expected = ChipSynth.loopSeconds(theme) * ChipSynth.sampleRate
            let rms = (samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count)).squareRoot()
            #expect(abs(Double(samples.count) - expected) < 200, "\(theme.rawValue) loop is the wrong length")
            #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 1 })
            #expect(rms > 0.02, "\(theme.rawValue) is too quiet")
            #expect(ChipSynth.loopSeconds(theme) > 15 && ChipSynth.loopSeconds(theme) < 60)
        }
    }
}

@MainActor
@Suite struct SoundCueTests {
    func newWorld() throws -> World {
        try World.newGame(NewGameConfig(airlineName: "Sound Air", airlineCode: "SA", homeAirport: "YEV", branding: .starter, difficulty: .easy, starterTypeID: "c208", seed: 8))
    }

    func makeEngine(_ settings: AppSettings = AppSettings(defaults: UserDefaults(suiteName: "bitairlines-test-\(UUID().uuidString)")!)) -> (AudioEngine, SilentAudioOutput, AppSettings) {
        let output = SilentAudioOutput()
        return (AudioEngine(output: output, settings: settings), output, settings)
    }

    @Test func nothingChangingMeansNoSound() throws {
        let w = try newWorld()
        #expect(SoundCues.between(WorldHeard(w), and: w).isEmpty)
    }

    @Test func openingARouteIsHeard() throws {
        var w = try newWorld()
        let heard = WorldHeard(w)
        try w.createRoute(stops: ["YEV", "YUB"])
        #expect(SoundCues.between(heard, and: w) == [.routeOpened])
        #expect(SoundCues.between(WorldHeard(w), and: w).isEmpty, "the same news is not heard twice")
    }

    @Test func aDeliveredAircraftIsHeard() throws {
        var w = try newWorld()
        let listing = try #require(w.market.listings.first { (AircraftCatalog.type($0.typeID)?.level ?? 9) <= 1 && $0.price < w.airline.cash })
        try w.buyUsed(listingID: listing.id)
        let heard = WorldHeard(w)
        w.advance(byMinutes: 120 * 1440)
        #expect(SoundCues.between(heard, and: w).contains(.arrival))
    }

    @Test func aCertificateUpgradeIsACelebration() {
        #expect(SoundCues.cue(for: .certificate) == .levelUp)
        #expect(SoundCues.cue(for: .routeOpened) == .routeOpened)
        #expect(SoundCues.cue(for: .loan) == nil, "money the player moved was already heard when they pressed the button")
    }

    @Test func theEnginePlaysOnlyTheStrongestSound() {
        let (engine, output, _) = makeEngine()
        engine.play(strongest: [.notice, .levelUp, .tap])
        #expect(output.effects == [.levelUp])
        engine.play(strongest: [])
        #expect(output.effects.count == 1)
    }

    @Test func theEngineObeysTheSettings() {
        let (engine, output, settings) = makeEngine()
        settings.soundEffects = false
        engine.play(.coin)
        #expect(output.effects.isEmpty)
        settings.soundEffects = true
        engine.play(.coin)
        #expect(output.effects == [.coin])
        engine.setSuspended(true)
        engine.play(.coin)
        #expect(output.effects.count == 1, "nothing plays while the app is in the background")
    }

    @Test func settingsAreRememberedAndDefaultToSoundOn() throws {
        let suite = "bitairlines-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let first = AppSettings(defaults: defaults)
        #expect(first.soundEffects && first.music && first.volume == .medium)
        first.music = false
        first.volume = .low
        let second = AppSettings(defaults: defaults)
        #expect(!second.music && second.volume == .low && second.soundEffects)
    }

    @Test func musicStartsStopsAndFollowsTheSetting() async throws {
        let (engine, output, settings) = makeEngine()
        engine.setMusic(.flying)
        for _ in 0..<150 where output.music == nil { try await Task.sleep(nanoseconds: 100_000_000) }
        #expect(output.music == .flying, "the loop is built in the background and then plays")
        settings.music = false
        #expect(output.music == nil)
        settings.music = true
        #expect(output.music == .flying)
        engine.setMusic(nil)
        #expect(output.music == nil)
    }
}
