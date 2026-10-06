import Testing
import Foundation
import CoreCatalog
import CoreWorld
@testable import BitAirlines

@Suite struct WordsTests {
    func check(_ text: String, _ what: String) {
        #expect(!text.isEmpty, "\(what) has no words")
        #expect(text.allSatisfy { $0.isASCII }, "\(what) uses a character the pixel font lacks")
        #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "\(what) has a dash")
    }

    @Test func everyNewThingHasPlainWords() {
        for kit in Kit.allCases { check(Words.name(kit), "kit"); check(Words.explain(kit), "kit") }
        for facility in Facility.allCases { check(Words.name(facility), "facility"); check(Words.explain(facility), "facility") }
        for perk in Perk.allCases { check(Words.name(perk), "perk"); check(Words.explain(perk), "perk") }
        for level in ServiceLevel.allCases { check(Words.name(level), "service") }
        for mode in GameMode.allCases { check(Words.name(mode), "mode"); check(Words.explain(mode), "mode") }
        for kind in JobKind.allCases { check(Words.name(kind), "job") }
        for kind in EventKind.allCases { check(Words.name(kind), "event"); check(Words.explain(kind, place: "YEV"), "event") }
        for group in RatingGroup.allCases { check(Words.name(group), "rating") }
        for def in ScenarioDefinition.all { check(Words.name(def.id), "scenario"); check(Words.goal(def), "scenario") }
        for medal in Medal.allCases { check(Words.name(medal), "medal") }
    }

    @Test func theBestMedalIsKept() throws {
        let defaults = try #require(UserDefaults(suiteName: "bitairlines-medals-\(UUID().uuidString)"))
        #expect(ScenarioRecords.best(.freezeUp, defaults: defaults) == nil)
        ScenarioRecords.record(.silver, for: .freezeUp, defaults: defaults)
        ScenarioRecords.record(.bronze, for: .freezeUp, defaults: defaults)
        #expect(ScenarioRecords.best(.freezeUp, defaults: defaults) == .silver)
        ScenarioRecords.record(.gold, for: .freezeUp, defaults: defaults)
        #expect(ScenarioRecords.best(.freezeUp, defaults: defaults) == .gold)
    }

    @Test func theRailHasEveryScreen() {
        #expect(GameSection.allCases.count == 9)
        #expect(Set(GameSection.allCases.map(\.title)).count == 9)
        #expect(GameSection.rail.count == 6, "six buttons on the rail")
        for s in GameSection.allCases where s != .airline { #expect(s.railButton.map { GameSection.rail.contains($0) } == true, "\(s) is reachable from the rail") }
    }

    @Test func aBusyWorldReadsCleanlyInTheNews() throws {
        var w = try World.newGame(NewGameConfig(airlineName: "News Air", airlineCode: "NA", homeAirport: "YEV", branding: .starter, difficulty: .easy, starterTypeID: "c208", seed: 12))
        let route = try w.createRoute(stops: ["YEV", "YUB"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        try w.build(.fuelDepot, at: "YEV")
        try w.buyFuel(kg: 5_000)
        w.startEvent(.miningBoom, at: "YUB")
        w.advance(byMinutes: 60 * 1440)
        for item in w.news { check(Messages.news(item, in: w), "news \(item.kind)") }
    }
}
