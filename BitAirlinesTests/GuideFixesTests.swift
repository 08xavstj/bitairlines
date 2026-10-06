import Testing
import Foundation
import CoreCatalog
import CoreWorld
@testable import BitAirlines

/// The guide after the first-session playtest: an unflyable first route, an aircraft away on a job, jobs taught early where
/// routes are thin, and tips that match what the screens show.
@MainActor
@Suite struct GuideFixesTests {
    func newWorld(home: String = "YEV") throws -> World {
        try World.newGame(NewGameConfig(airlineName: "Guide Air", airlineCode: "GA", homeAirport: home, branding: .starter, difficulty: .easy, starterTypeID: "c208", seed: 3))
    }

    @Test func aRouteNoAircraftCanFlySendsThePlayerBackToStepOne() throws {
        var w = try newWorld()
        // Iqaluit is far beyond a Caravan's range from Inuvik.
        _ = try w.createRoute(stops: ["YEV", "YFB"])
        #expect(Tutorial.step(world: w, speed: .paused, seen: []) == .openRoute)
        let text = Tutorial.text(for: .openRoute, world: w, suggestion: nil, flights: 0)
        #expect(text.contains("cannot fly"))
        _ = try w.createRoute(stops: ["YEV", "YUB"])
        #expect(Tutorial.step(world: w, speed: .paused, seen: []) == .assignAircraft)
    }

    @Test func anAircraftAwayOnAJobIsNotParked() throws {
        var w = try newWorld()
        let route = try w.createRoute(stops: ["YEV", "YUB"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        for _ in 0..<30 where w.airline.stats.flights < Tutorial.flightsToWatch { w.advance(byMinutes: 1440) }
        let planeID = w.aircraft[0].id
        // The job board is random: take the first job the aircraft can fly, if there is one.
        let jobs = w.ops.jobs.map(\.id)
        guard let jobID = jobs.first(where: { w.jobProblem(jobID: $0, aircraftID: planeID) == nil }) else { return }
        try w.takeJob(jobID: jobID, aircraftID: planeID)
        #expect(w.routes.allSatisfy { $0.aircraftIDs.isEmpty })
        #expect(Tutorial.step(world: w, speed: .x1, seen: [.review]) != .assignAircraft)
    }

    @Test func jobsComeEarlyWhereRoutesAreThin() throws {
        var w = try newWorld()
        let route = try w.createRoute(stops: ["YEV", "YUB"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        for _ in 0..<30 where w.airline.stats.flights < Tutorial.flightsToWatch { w.advance(byMinutes: 1440) }
        #expect(Tutorial.step(world: w, speed: .x1, seen: [.review]) == .money)
        #expect(Tutorial.step(world: w, speed: .x1, seen: [.review], jobsEarly: true) == .jobs)
        #expect(Tutorial.routesAreThin(nil))
        #expect(Tutorial.routesAreThin((code: "YUB", perDay: 200)))
        #expect(!Tutorial.routesAreThin((code: "YMA", perDay: 2_600)))
        #expect(TutorialStep.tourJobsEarly.count == TutorialStep.tour.count && Set(TutorialStep.tourJobsEarly) == Set(TutorialStep.tour))
        #expect(TutorialStep.tourJobsEarly.last == TutorialStep.tour.last)
    }

    @Test func theMoneyTipSaysTheFirstDayShowsTomorrow() throws {
        let w = try newWorld()
        #expect(w.books.isEmpty)
        #expect(Tutorial.text(for: .money, world: w, suggestion: nil, flights: 0).contains("tomorrow"))
        #expect(!Tutorial.text(for: .inbox, world: w, suggestion: nil, flights: 0).contains("bad weather"), "weather is a notice, not a stop")
    }
}
