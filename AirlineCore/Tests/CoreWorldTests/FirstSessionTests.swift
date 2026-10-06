import Testing
import CoreCatalog
@testable import CoreWorld

/// The first session should pay: the first route is fully known from its first flight, the guided route makes money in its
/// first week (in January at a polar base), and a second aircraft is within reach.
@Suite struct FirstSessionTests {
    @Test func onlyTheFirstRouteStartsFullyKnown() throws {
        var w = try Fixtures.world()
        #expect(w.opensFirstRoute)
        let first = try w.createRoute(stops: ["YEV", "YUB"])
        #expect(!w.opensFirstRoute)
        let second = try w.createRoute(stops: ["YEV", "YSY"])
        let firstRoute = try #require(w.routes.first { $0.id == first })
        let secondRoute = try #require(w.routes.first { $0.id == second })
        #expect(firstRoute.legs.allSatisfy { $0.maturity == Tuning.firstRouteMaturity })
        #expect(secondRoute.legs.allSatisfy { $0.maturity == Tuning.minimumMaturity })

        // Closing the first route and opening it again does not give a second head start.
        try w.deleteRoute(id: first)
        let again = try w.createRoute(stops: ["YEV", "YUB"])
        let reopened = try #require(w.routes.first { $0.id == again })
        #expect(reopened.legs.allSatisfy { $0.maturity == Tuning.minimumMaturity })
    }

    @Test func theGuidedFirstRoutePaysInItsFirstWeek() throws {
        var w = try Fixtures.world()
        w.setPausePolicy(.never)
        // The route the guide suggests: the best idea from home (Tutorial.suggestion in the app).
        let home = w.airline.home
        let ideas = w.routeIdeas(limit: 20)
        let idea = try #require(ideas.first { $0.stops.first == home && $0.stops.count == 2 })
        let routeID = try w.createRoute(stops: idea.stops)
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: routeID)
        w.advance(byMinutes: 7 * 1440)
        let route = try #require(w.routes.first { $0.id == routeID })
        print("CALIBRATION first week \(idea.stops.joined(separator: "-")): revenue \(route.sinceOpened.revenue), cost \(route.sinceOpened.cost), flights \(route.sinceOpened.flights)")
        #expect(route.sinceOpened.flights > 0)
        #expect(route.sinceOpened.profit > 0, "the guided route earns more than it costs in its first week")
    }

    @Test func aSecondAircraftIsWithinReachAtTheStart() throws {
        for difficulty in [Difficulty.easy, .standard] {
            var w = try Fixtures.world(difficulty: difficulty)
            let starter = try #require(World.starterOffers(home: "YEV", difficulty: difficulty).first { $0.typeID == "c208" })
            #expect(w.airline.cash - Tuning.nextStepCashReserve >= starter.price, "another aircraft like the first one is affordable on \(difficulty)")

            let routeID = try w.createRoute(stops: ["YEV", "YUB"])
            try w.assign(aircraftID: w.aircraft[0].id, toRoute: routeID)
            let step = w.nextStep
            if case .buyAircraft(_, let price) = step {
                #expect(price <= w.airline.cash)
            } else {
                Testing.Issue.record("expected a used aircraft to buy, got \(step)")
            }
        }
    }
}
