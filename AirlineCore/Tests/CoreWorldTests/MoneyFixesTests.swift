import Testing
import CoreCatalog
@testable import CoreWorld

/// Playtest fixes around money: route sales that cannot be farmed, one market per pair, schedules that follow the fleet,
/// pilots and staff paid and let go fairly, fuel stock booked honestly, and a qualify notice that is not a bill.
@Suite struct MoneyFixesTests {
    // MARK: Selling a route

    @Test func aYoungRouteSellsForNothingAndAnOlderOneForItsProvenProfit() throws {
        var w = try Fixtures.flyingWorld()
        let id = w.routes[0].id
        // A great first day is not enough: the route must have flown a few weeks.
        w.routes[0].book.today = RouteDay(revenue: 50_000, flightCost: 1_000)
        w.routes[0].book.sinceOpened = RouteDay(revenue: 50_000, flightCost: 1_000)
        #expect(w.routeSalePrice(routeID: id) == 0)
        w.routes[0].openedDay = w.clock.dayIndex - (Tuning.routeSaleMinimumDays - 1)
        #expect(w.routeSalePrice(routeID: id) == 0)

        // Half a year at $1,000 a day since it opened: 60 days of that, scaled to half a year.
        let days = 182
        w.routes[0].openedDay = w.clock.dayIndex - days
        w.routes[0].book.sinceOpened = RouteDay(revenue: days * 3_000, flightCost: days * 2_000)
        let expected = Int((1_000.0 * Double(Tuning.routeSaleDays) * (Double(days) / Double(Tuning.routeSaleFullPriceDays))).rounded())
        #expect(w.routeSalePrice(routeID: id) == expected)
    }

    @Test func theBuyerKeepsFlyingThePairSoReopeningItMeansSharingIt() throws {
        var w = try Fixtures.flyingWorld()
        try #require(!w.ops.rivals.isEmpty)
        let before = try #require(w.routes.first)
        let a = try Fixtures.airport("YEV"), b = try Fixtures.airport("YUB")
        let leg = try #require(before.legs.first { $0.from == "YEV" })
        let alone = w.capture(route: before, leg: leg, from: a, to: b)
        let price = try w.sellRoute(routeID: before.id)
        #expect(price == 0, "sold on its first day: nothing to pay for")
        #expect(!w.rivalRoutes("YEV", "YUB").isEmpty, "the operator who bought it flies it now")

        let again = try w.createRoute(stops: ["YEV", "YUB"])
        let reopened = try #require(w.routes.first { $0.id == again })
        let sameLeg = try #require(reopened.legs.first { $0.from == "YEV" })
        let shared = w.capture(route: reopened, leg: sameLeg, from: a, to: b)
        #expect(shared < alone * 0.8, "\(shared) against \(alone)")
    }

    // MARK: One market per pair

    @Test func aSecondRouteOnThePairSharesItsMarket() throws {
        var w = try Fixtures.world()
        let first = try w.createRoute(stops: ["YEV", "YUB"])
        let whole = market(w, route: first)
        let second = try w.createRoute(stops: ["YEV", "YUB"])
        let one = market(w, route: first), two = market(w, route: second)
        #expect(whole > 0)
        #expect(abs(one - whole / 2) < 1e-9 && abs(two - whole / 2) < 1e-9, "two routes, one market")

        try w.deleteRoute(id: second)
        let back = market(w, route: first)
        #expect(abs(back - whole) < 1e-9, "closing the copy gives the market back")
    }

    /// People a day wanting the first leg of a route (0 if it is gone).
    func market(_ w: World, route id: Int) -> Double {
        w.routes.first { $0.id == id }?.legs.first?.marketPaxPerDay ?? 0
    }

    // MARK: Schedules follow the fleet

    @Test func closingASharedAircraftsOtherRouteGivesThisOneTheWholeAircraft() throws {
        var w = try Fixtures.world()
        let plane = w.aircraft[0].id
        let north = try w.createRoute(stops: ["YEV", "YUB"])
        let south = try w.createRoute(stops: ["YEV", "YZF"])
        try w.assign(aircraftID: plane, toRoute: north)
        try w.addRoute(aircraftID: plane, routeID: south)
        let halved = w.routes.first { $0.id == south }?.frequency ?? 0
        try w.deleteRoute(id: north)
        let whole = w.routes.first { $0.id == south }?.frequency ?? 0
        #expect(whole > halved, "\(whole) after closing the other route, \(halved) before")
    }

    // MARK: Pilots and staff

    @Test func aFinishedCourseCountsAtOnce() throws {
        var w = try Fixtures.world()
        w.ops.pilots[0].trainingFor = .twinProps
        w.ops.pilots[0].trainingUntilMinute = w.clock.minute + 60
        w.advance(byMinutes: 1440)
        let pilot = w.ops.pilots[0]
        #expect(pilot.isRated(.twinProps) && pilot.trainingFor == nil)
    }

    @Test func aSparePilotCanBeLetGoButNotTheOnlyCrew() throws {
        var w = try Fixtures.world()
        let crew = w.ops.pilots[0].id
        #expect(w.isNeededCrew(pilotID: crew))
        var refused: WorldError?
        do { try w.dismissPilot(id: crew) } catch let error as WorldError { refused = error }
        #expect(refused == .invalidChoice)

        var spare = w.makePilot(group: .singles)
        spare.aircraftID = nil
        w.ops.pilots.append(spare)
        #expect(!w.isNeededCrew(pilotID: crew), "a spare rated on the type could step in")
        let payroll = w.pilotPayroll
        try w.dismissPilot(id: spare.id)
        #expect(w.ops.pilots.count == 1 && w.pilotPayroll < payroll)

        // The crew of an aircraft that has gone is spare at once, not from next Monday.
        w.ops.pilots[0].aircraftID = 999
        #expect(w.isSpare(w.ops.pilots[0]))
    }

    @Test func salariesArePaidADayAtATime() throws {
        var staffed = try Fixtures.world()
        var plain = staffed
        try staffed.hire(.revenueManager)
        staffed.advance(byMinutes: 1440)
        plain.advance(byMinutes: 1440)
        // Hiring after payday and letting go before it no longer saves the salary.
        #expect(staffed.salariesPerDay > plain.salariesPerDay)
        #expect(staffed.today.overhead - plain.today.overhead == staffed.salariesPerDay - plain.salariesPerDay)
    }

    // MARK: Fuel bought ahead

    @Test func fuelBoughtAheadIsAnInvestmentUntilItIsBurned() throws {
        var w = try Fixtures.flyingWorld()
        let overhead = w.today.overhead, invested = w.today.investments, cash = w.airline.cash
        let price = w.fuelPrice(kg: 10_000)
        try w.buyFuel(kg: 10_000)
        #expect(w.airline.cash == cash - price)
        #expect(w.today.overhead == overhead, "fuel in the tanks is not a running cost")
        #expect(w.today.investments == invested + price)
        #expect(w.ops.fuel.investedKg == 10_000)
        w.advance(byMinutes: 2 * 1440)
        #expect(w.ops.fuel.investedKg < 10_000, "flights drew on the stock")
        // What was burned left the investment line and went into the flights' costs.
        let stillInvested = w.books.reduce(0) { $0 + $1.investments } + w.today.investments
        #expect(stillInvested < price)
    }

    // MARK: Certificate notice

    @Test func theQualifyNoticeIsNotABill() throws {
        var w = try Fixtures.world()
        w.airline.stats.revenue = 2_000_000
        w.airline.reputation = 20
        w.advance(byMinutes: 2 * 1440)
        let notice = try #require(w.issues.first { if case .certificateReady = $0.kind { return true } else { return false } })
        #expect(notice.options.allSatisfy { $0.costUSD == 0 })
        #expect(w.airline.level == 1, "nothing is bought until the player buys it")
    }
}
