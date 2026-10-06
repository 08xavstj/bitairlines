import Testing
import Foundation
import CoreCatalog
import CoreWorld
@testable import BitAirlines

@MainActor
@Suite struct TutorialTests {
    func newWorld(home: String = "YEV", type: String = "c208") throws -> World {
        try World.newGame(NewGameConfig(airlineName: "Guide Air", airlineCode: "GA", homeAirport: home, branding: .starter, difficulty: .easy, starterTypeID: type, seed: 3))
    }

    func scratchStore() throws -> TutorialStore {
        TutorialStore(defaults: try #require(UserDefaults(suiteName: "bitairlines-tutorial-\(UUID().uuidString)")))
    }

    @Test func theStepsFollowWhatThePlayerDid() throws {
        var w = try newWorld()
        #expect(Tutorial.step(world: w, speed: .paused, seen: []) == .openRoute)

        let route = try w.createRoute(stops: ["YEV", "YUB"])
        #expect(Tutorial.step(world: w, speed: .paused, seen: []) == .assignAircraft)

        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        #expect(Tutorial.step(world: w, speed: .paused, seen: []) == .startClock)
        #expect(Tutorial.step(world: w, speed: .x4, seen: []) == .watch)

        for _ in 0..<60 where w.airline.stats.flights < Tutorial.flightsToWatch { w.advance(byMinutes: 1440) }
        #expect(w.airline.stats.flights >= Tutorial.flightsToWatch)
        #expect(Tutorial.step(world: w, speed: .x4, seen: []) == .review)
        #expect(Tutorial.step(world: w, speed: .paused, seen: []) == .review, "pausing at the end does not send the player back")
        #expect(Tutorial.step(world: w, speed: .x4, seen: [.review]) == .money)
        #expect(Tutorial.step(world: w, speed: .x4, seen: [.review, .money, .inbox]) == .hangar)
        #expect(Tutorial.step(world: w, speed: .x4, seen: Set(TutorialStep.tour)) == nil)
    }

    @Test func buyingAndOpeningFinishTheirStepsWithoutNext() throws {
        var w = try newWorld()
        w.airline.cash = 30_000_000
        let route = try w.createRoute(stops: ["YEV", "YUB"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        for _ in 0..<60 where w.airline.stats.flights < Tutorial.flightsToWatch { w.advance(byMinutes: 1440) }
        let read: Set<TutorialStep> = [.review, .money, .inbox]
        #expect(Tutorial.step(world: w, speed: .x4, seen: read) == .hangar)
        let listing = try #require(w.market.listings.first { (AircraftCatalog.type($0.typeID)?.level ?? 9) <= 1 })
        try w.buyUsed(listingID: listing.id)
        #expect(Tutorial.step(world: w, speed: .x4, seen: read) == .secondRoute)
        _ = try w.createRoute(stops: ["YEV", "YSY"])
        #expect(Tutorial.step(world: w, speed: .x4, seen: read) == .jobs)
    }

    @Test func everyTipHasAButtonToMoveOn() {
        for step in TutorialStep.tour { #expect(step.needsNext || step.canPutOff, "\(step)") }
        #expect(TutorialStep.tour.last == .level)
    }

    @Test func everyStepHasPlainWordsAndNoDashes() throws {
        let w = try newWorld()
        let suggestion = Tutorial.suggestion(world: w)
        for step in TutorialStep.allCases {
            for flights in [0, 2, 5] {
                let text = Tutorial.text(for: step, world: w, suggestion: suggestion, flights: flights)
                #expect(!text.isEmpty && text.allSatisfy { $0.isASCII }, "\(step)")
                #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "no dashes in player text")
            }
        }
    }

    @Test func eachStepPointsAtOneControl() {
        #expect(TutorialStep.openRoute.section == GameSection.map)
        #expect(TutorialStep.assignAircraft.section == GameSection.fleet)
        #expect(TutorialStep.review.section == GameSection.routes)
        #expect(TutorialStep.startClock.highlightsSpeed)
        #expect(!TutorialStep.watch.highlightsSpeed && TutorialStep.watch.section == nil)
    }

    @Test func theSuggestionIsARouteTheStarterCanFly() throws {
        for (home, type) in [("YEV", "c208"), ("BET", "c208")] {
            let w = try newWorld(home: home, type: type)
            let suggestion = try #require(Tutorial.suggestion(world: w), "\(home) should have a first route to try")
            #expect(suggestion.perDay > 0)
            #expect(w.routeProblem(stops: [home, suggestion.code]) == nil)
            let plane = try #require(w.aircraft.first?.type)
            #expect(w.fitProblem(type: plane, route: Route.probe(w, [home, suggestion.code])) == nil)
        }
    }

    @Test func theGuideIsRememberedPerSlotAndEndsForGood() throws {
        let store = try scratchStore()
        #expect(!store.isActive(slot: 0), "an old save never shows the guide")
        store.setActive(true, slot: 0)
        #expect(store.isActive(slot: 0) && !store.isActive(slot: 1))

        var w = try newWorld()
        let coach = TutorialCoach(slot: 0, store: store)
        #expect(coach.active)
        coach.update(world: w, speed: .paused)
        #expect(coach.step == .openRoute)

        let route = try w.createRoute(stops: ["YEV", "YUB"])
        coach.update(world: w, speed: .paused)
        #expect(coach.step == .assignAircraft)

        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        coach.update(world: w, speed: .x1)
        #expect(coach.step == .watch)

        coach.finish()
        #expect(!coach.active && coach.step == nil)
        #expect(!store.isActive(slot: 0), "once skipped it stays skipped")
        #expect(!TutorialCoach(slot: 0, store: store).active)
    }

    @Test func goingThroughEveryTipEndsTheGuide() throws {
        let store = try scratchStore()
        store.setActive(true, slot: 2)
        var w = try newWorld()
        let route = try w.createRoute(stops: ["YEV", "YUB"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        for _ in 0..<60 where w.airline.stats.flights < Tutorial.flightsToWatch { w.advance(byMinutes: 1440) }
        let coach = TutorialCoach(slot: 2, store: store)
        coach.update(world: w, speed: .x1)
        #expect(coach.step == .review)
        for _ in TutorialStep.tour { coach.next(world: w, speed: .x1) }
        #expect(!coach.active && !store.isActive(slot: 2))
    }
}

extension Route {
    /// A route through the stops, for asking whether an aircraft could fly it, without adding it to a world.
    static func probe(_ world: World, _ stops: [String]) -> Route {
        var copy = world
        let id = (try? copy.createRoute(stops: stops)) ?? 0
        return copy.routes.first { $0.id == id } ?? copy.routes[0]
    }
}
