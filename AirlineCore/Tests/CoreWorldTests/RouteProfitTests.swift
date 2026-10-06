import Foundation
import Testing
import CoreCatalog
@testable import CoreWorld

@Suite struct RouteProfitTests {
    /// A Caravan on one route for a week, starting at a stop of the route (so no repositioning flight).
    private func flownWeek() throws -> World {
        var w = try Fixtures.flyingWorld()
        Fixtures.light(&w, "YUB")
        #expect(w.advance(byMinutes: 7 * 1440) == .reachedTarget)
        return w
    }

    @Test func aRouteBooksWhatTheAirlineEarnsAndSpendsOnIt() throws {
        let w = try flownWeek()
        let route = w.routes[0]
        let book = route.sinceOpened
        let flightCosts = w.books.reduce(0) { $0 + $1.flightCosts } + w.today.flightCosts
        let revenue = w.books.reduce(0) { $0 + $1.revenue } + w.today.revenue

        #expect(book.flights > 10, "flights: \(book.flights)")
        #expect(book.flights == w.airline.stats.flights)
        #expect(book.passengers == w.airline.stats.passengers)
        #expect(book.revenue == revenue && book.revenue == w.airline.stats.revenue)
        #expect(book.flightCost == flightCosts)
        #expect(book.revenue - book.flightCost == revenue - flightCosts)

        // One aircraft's fixed cost for each of the 7 midnights; head office is left out.
        let type = try Fixtures.type("c208")
        #expect(book.aircraftCost == 7 * Int(LegEconomics.fixedPerDay(type: type).rounded()))
        #expect(book.profit == book.revenue - book.flightCost - book.aircraftCost)

        let load = try #require(book.seatLoad)
        #expect(load > 0 && load <= 1)
    }

    @Test func theLastSevenDaysIsTodayAndTheSixDaysBefore() throws {
        let w = try flownWeek()
        let route = w.routes[0]
        #expect(route.book.recentDays == Route.bookDays)
        let window = w.books.suffix(Route.bookDays - 1)
        let revenue = window.reduce(0) { $0 + $1.revenue } + w.today.revenue
        let flightCosts = window.reduce(0) { $0 + $1.flightCosts } + w.today.flightCosts
        #expect(route.revenueLast7Days == revenue)
        #expect(route.last7Days.flightCost == flightCosts)
        #expect(route.costLast7Days == flightCosts + route.last7Days.aircraftCost)
        #expect(route.profitLast7Days == route.revenueLast7Days - route.costLast7Days)
        #expect(route.seatLoadLast7Days != nil)
        // The first day has dropped out of the window but stays in the total.
        #expect(route.sinceOpened.revenue >= route.revenueLast7Days)
    }

    @Test func aNewRouteHasAnEmptyBook() throws {
        var w = try Fixtures.world()
        let id = try w.createRoute(stops: ["YEV", "YUB"])
        let route = try #require(w.routes.first { $0.id == id })
        #expect(route.profitLast7Days == 0 && route.costLast7Days == 0 && route.revenueLast7Days == 0)
        #expect(route.seatLoadLast7Days == nil)
        #expect(route.book.recentDays == 1)
    }

    @Test func anOldRouteWithoutABookStillLoads() throws {
        let w = try flownWeek()
        #expect(w.routes[0].bookStore != nil)

        // A save from before the field existed: the same world with no books (a nil optional is left out of the JSON).
        var stripped = w
        for r in stripped.routes.indices { stripped.routes[r].bookStore = nil }
        let old = try Fixtures.encode(stripped)
        #expect(!(String(data: old, encoding: .utf8) ?? "").contains("bookStore"))

        var loaded = try JSONDecoder().decode(World.self, from: old)
        #expect(loaded.routes[0].bookStore == nil)
        #expect(loaded.routes[0].profitLast7Days == 0)
        #expect(loaded.routes[0].revenueThisMonth == w.routes[0].revenueThisMonth)

        loaded.advance(byMinutes: 2 * 1440)
        #expect(loaded.routes[0].bookStore != nil)
        #expect(loaded.routes[0].sinceOpened.flights > 0, "the book starts once the save is loaded")

        // A single route on its own decodes too.
        var route = w.routes[0]
        route.bookStore = nil
        let routeJSON = try JSONEncoder().encode(route)
        #expect(!(String(data: routeJSON, encoding: .utf8) ?? "").contains("bookStore"))
        let decoded = try JSONDecoder().decode(Route.self, from: routeJSON)
        #expect(decoded.book == RouteBook())
        #expect(decoded.stops == w.routes[0].stops)
    }
}
