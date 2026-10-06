import Testing
import CoreCatalog
@testable import CoreWorld

@Suite struct RouteTests {
    @Test func createsACycleOfLegs() throws {
        var w = try Fixtures.world()
        let id = try w.createRoute(stops: ["YEV", "YUB", "YSY"])
        let route = try #require(w.routes.first { $0.id == id })
        #expect(route.legs.count == 3)
        #expect(route.legs[0].from == "YEV" && route.legs[0].to == "YUB")
        #expect(route.legs[2].from == "YSY" && route.legs[2].to == "YEV")
        #expect(route.name == "YEV-YUB-YSY")
        #expect(route.frequency == 2 && route.fareMultiplier == 1)
        #expect(route.legs.allSatisfy { $0.marketPaxPerDay > 0 && $0.marketFare > 0 && $0.maturity == Tuning.minimumMaturity })
        #expect(w.news.last?.kind == .routeOpened)
    }

    @Test func twoStopsMakeAReturnTrip() throws {
        var w = try Fixtures.world()
        let id = try w.createRoute(stops: ["YEV", "YUB"])
        let route = try #require(w.routes.first { $0.id == id })
        #expect(route.legs.map(\.from) == ["YEV", "YUB"] && route.legs.map(\.to) == ["YUB", "YEV"])
    }

    @Test func rejectsBadRoutes() throws {
        let w = try Fixtures.world()
        #expect(w.routeProblem(stops: ["YEV"]) == .routeNeedsTwoStops)
        #expect(w.routeProblem(stops: ["YEV", "YEV"]) == .duplicateStops)
        #expect(w.routeProblem(stops: ["YEV", "ZZZ"]) == .unknownAirport("ZZZ"))
        #expect(w.routeProblem(stops: ["YEV", "YUB", "YSY", "YPC", "YHI", "YCO", "YZF"]) == .tooManyStops)
        #expect(w.routeProblem(stops: ["YEV", "YEG"]) == .airportLevelTooHigh(airport: "YEG", required: 4))
        #expect(w.routeProblem(stops: ["YEV", "OTZ"]) == .permitRequired(country: "US", price: 1_000_000))
        #expect(w.routeProblem(stops: ["YEV", "YUB"]) == nil)
    }

    @Test func permitsOpenForeignAirports() throws {
        var w = try Fixtures.world()
        w.airline.cash = 2_000_000
        try w.buyPermit(country: "US")
        #expect(w.airline.permits.contains("US") && w.airline.cash == 1_000_000)
        #expect(w.routeProblem(stops: ["YEV", "OTZ"]) == nil)
        #expect(throws: WorldError.alreadyHasPermit) { try w.buyPermit(country: "US") }
    }

    @Test func aircraftMustFitTheRoute() throws {
        var w = try Fixtures.world()
        let id = try w.createRoute(stops: ["YEV", "YUB"])
        let route = try #require(w.routes.first { $0.id == id })
        let jet = try #require(AircraftCatalog.type("b738"))
        #expect(w.fitProblem(type: jet, route: route) == .aircraftCannotUse(airport: "YEV"))
        let floats = try #require(AircraftCatalog.type("dhc6f"))
        #expect(w.fitProblem(type: floats, route: route) == .aircraftCannotUse(airport: "YEV"))
        let caravan = try #require(AircraftCatalog.type("c208"))
        #expect(w.fitProblem(type: caravan, route: route) == nil)
        let far = try w.createRoute(stops: ["YEV", "YZF"])
        let c172 = try #require(AircraftCatalog.type("c172"))
        #expect(w.fitProblem(type: c172, route: try #require(w.routes.first { $0.id == far })) == .outOfRange(km: 1087))
    }

    @Test func assigningPutsTheAircraftToWork() throws {
        var w = try Fixtures.world()
        let id = try w.createRoute(stops: ["YEV", "YUB"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: id)
        #expect(w.aircraft[0].routeID == id)
        #expect(w.routes[0].aircraftIDs == [w.aircraft[0].id])
        if case .boarding = w.aircraft[0].status {} else { Issue.record("an aircraft at the first stop should start boarding") }
    }

    @Test func anAircraftElsewhereFliesToTheRouteFirst() throws {
        var w = try Fixtures.world()
        let id = try w.createRoute(stops: ["YUB", "YSY"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: id)
        guard case .flying = w.aircraft[0].status else { Issue.record("should be ferrying to Tuktoyaktuk"); return }
        #expect(w.aircraft[0].flight?.isFerry == true && w.aircraft[0].flight?.to == "YUB")
        w.advance(byMinutes: 3 * 60)
        #expect(w.airline.stats.flights >= 0)
        #expect(w.aircraft[0].location == "YUB" || w.aircraft[0].location == "YSY")
    }

    @Test func unassigningParksTheAircraft() throws {
        var w = try Fixtures.flyingWorld()
        try w.unassign(aircraftID: w.aircraft[0].id)
        #expect(w.aircraft[0].routeID == nil && w.routes[0].aircraftIDs.isEmpty)
        w.advance(byMinutes: 2 * 1440)
        #expect(w.aircraft[0].status == .idle)
    }

    @Test func deletingARouteFreesItsAircraft() throws {
        var w = try Fixtures.flyingWorld()
        try w.deleteRoute(id: 1)
        #expect(w.routes.isEmpty && w.aircraft[0].routeID == nil)
    }

    @Test func fareFrequencyAreClamped() throws {
        var w = try Fixtures.flyingWorld()
        try w.setFare(routeID: 1, multiplier: 9)
        try w.setFrequency(routeID: 1, perDay: 0)
        #expect(w.routes[0].fareMultiplier == Route.maxFare && w.routes[0].frequency == Route.minFrequency)
        try w.setFare(routeID: 1, multiplier: 0.1)
        try w.setFrequency(routeID: 1, perDay: 500)
        #expect(w.routes[0].fareMultiplier == Route.minFare && w.routes[0].frequency == Route.maxFrequency)
        #expect(throws: WorldError.unknownRoute(99)) { try w.setFare(routeID: 99, multiplier: 1) }
    }

    @Test func airportGatesFollowTheCatchmentSize() throws {
        #expect(Progression.requiredLevel(for: try #require(AirportCatalog.airport("YUB"))) == 1)
        #expect(Progression.requiredLevel(for: try #require(AirportCatalog.airport("YZF"))) == 1)
        #expect(Progression.requiredLevel(for: try #require(AirportCatalog.airport("YEG"))) == 4)
        #expect(Progression.requiredLevel(for: try #require(AirportCatalog.airport("LHR"))) == 5)
        #expect(Progression.requiredLevel(for: try #require(AirportCatalog.airport("HND"))) == 6)
    }
}
