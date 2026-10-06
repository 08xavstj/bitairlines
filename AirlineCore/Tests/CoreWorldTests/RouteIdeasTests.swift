import Testing
import CoreCatalog
@testable import CoreWorld

@Suite struct RouteIdeasTests {
    /// The route as it would be once opened, made on a copy so the world itself does not change.
    func opened(_ w: World, _ stops: [String]) throws -> Route {
        var copy = w
        let id = try copy.createRoute(stops: stops)
        let found = copy.routes.first { $0.id == id }
        return try #require(found)
    }

    @Test func aNewAirlineGetsRoutesItCanFlyBestFirst() throws {
        let w = try Fixtures.world()
        let ideas = w.routeIdeas()
        print("CALIBRATION route ideas YEV Caravan: " + ideas.map { "\($0.id) \($0.typeID) \(Int($0.profitPerDay))/day \($0.reason.rawValue) \($0.place)" }.joined(separator: "; "))
        #expect(ideas.count >= 2)
        #expect(ideas.count <= 5)
        let profits = ideas.map(\.profitPerDay)
        #expect(profits == profits.sorted(by: >))
        let ids = Set(ideas.map(\.id))
        #expect(ids.count == ideas.count)
        for idea in ideas {
            #expect(idea.profitPerDay > 0, "\(idea.id)")
            #expect(idea.stops.count == 2, "\(idea.id)")
            #expect(idea.stops.first == "YEV", "a new airline only flies from home: \(idea.id)")
            #expect(idea.typeID == "c208", "\(idea.id)")
            let problem = w.routeProblem(stops: idea.stops)
            #expect(problem == nil, "\(idea.id)")
            let type = try Fixtures.type(idea.typeID)
            let route = try opened(w, idea.stops)
            let fit = w.fitProblem(type: type, route: route)
            #expect(fit == nil, "\(idea.id)")
        }
    }

    @Test func theSameWorldGivesTheSameIdeas() throws {
        let w = try Fixtures.world()
        let first = w.routeIdeas(limit: 8)
        let second = w.routeIdeas(limit: 8)
        #expect(first == second)
        let fewer = w.routeIdeas(limit: 2)
        #expect(fewer == Array(first.prefix(2)))
    }

    @Test func routesAlreadyFlownAreNotSuggested() throws {
        var w = try Fixtures.world()
        let before = w.routeIdeas()
        let top = try #require(before.first)
        let routeID = try w.createRoute(stops: top.stops)
        #expect(routeID > 0)

        let after = w.routeIdeas()
        #expect(!after.isEmpty)
        let topAgain = after.contains { $0.id == top.id }
        #expect(!topAgain, "the route just opened is not suggested again")
        let reversed = after.contains { $0.stops == [top.stops[1], top.stops[0]] }
        #expect(!reversed, "nor the same route the other way round")
        let flown = w.routes.flatMap(\.legs).map { [$0.from, $0.to].sorted() }
        for idea in after {
            let duplicate = flown.contains(idea.stops.sorted())
            #expect(!duplicate, "\(idea.id) is already flown")
        }
    }

    @Test func theIdleStarterCanBeAssignedToAnIdea() throws {
        var w = try Fixtures.world()
        let ideas = w.routeIdeas()
        let top = try #require(ideas.first)
        let planeID = try #require(w.idleAircraftID(for: top))
        #expect(planeID == w.aircraft[0].id)

        let routeID = try w.createRoute(stops: top.stops)
        try w.assign(aircraftID: planeID, toRoute: routeID)
        let assigned = w.aircraft[0].routeID
        #expect(assigned == routeID)
        let next = w.routeIdeas()
        let busy = next.compactMap { w.idleAircraftID(for: $0) }
        #expect(busy.isEmpty, "the only aircraft is on a route now")
    }

    @Test func anAirlineWithNoAircraftIsJudgedForTheCheapestItCouldBuy() throws {
        var w = try Fixtures.world()
        w.aircraft.removeAll()
        let types = w.ideaTypes()
        #expect(types.count == 1)
        let cheapest = AircraftCatalog.available(atLevel: w.airline.level).map(\.priceUSD).min()
        #expect(types.first?.priceUSD == cheapest)
    }
}
