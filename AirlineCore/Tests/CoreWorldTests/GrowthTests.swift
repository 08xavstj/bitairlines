import Foundation
import Testing
import CoreCatalog
@testable import CoreWorld

@Suite struct GrowthTests {
    /// A week of books where the route made `profitPerDay` every day.
    func week(profitPerDay: Int) -> RouteBook {
        var book = RouteBook()
        let day = RouteDay(revenue: 3_000 + profitPerDay, flightCost: 2_500, aircraftCost: 500, passengers: 20, seats: 36, flights: 4)
        book.pastDays = Array(repeating: day, count: Route.bookDays - 1)
        book.today = day
        return book
    }

    /// A route open for a year that made `profitPerDay` every day: the sale price is worked out from its proven profit since it
    /// opened, and only a route flown a year fetches the full `Tuning.routeSaleDays` (the last week alone no longer sets it).
    func establish(_ w: inout World, routeIndex r: Int, profitPerDay: Int) {
        let days = Tuning.routeSaleFullPriceDays
        w.routes[r].openedDay = w.clock.dayIndex - days
        var book = week(profitPerDay: profitPerDay)
        book.sinceOpened = RouteDay(revenue: days * (3_000 + profitPerDay), flightCost: days * 2_500, aircraftCost: days * 500,
                                    passengers: days * 20, seats: days * 36, flights: days * 4)
        w.routes[r].book = book
    }

    // MARK: Selling a route

    @Test func sellingAProfitableRoutePaysAndALosingOnePaysNothing() throws {
        var w = try Fixtures.flyingWorld()
        let routeID = w.routes[0].id
        let name = w.routes[0].name
        establish(&w, routeIndex: 0, profitPerDay: 1_000)
        let quoted = w.routeSalePrice(routeID: routeID)
        #expect(quoted == 1_000 * Tuning.routeSaleDays)

        let before = w.airline.cash
        let paid = try w.sellRoute(routeID: routeID)
        #expect(paid == quoted)
        #expect(w.airline.cash - before == quoted)
        #expect(w.routes.isEmpty)
        let planeRoute = w.aircraft[0].routeID
        #expect(planeRoute == nil, "the aircraft is free again")
        let last = try #require(w.news.last)
        #expect(last.kind == .growth)
        #expect(last.subject == "sold:" + name)
        #expect(last.amount == quoted)

        let losing = try w.createRoute(stops: ["YEV", "YUB"])
        let r = try #require(w.routeIndex(losing))
        establish(&w, routeIndex: r, profitPerDay: -400)
        let losingQuote = w.routeSalePrice(routeID: losing)
        #expect(losingQuote == 0)
        let cash = w.airline.cash
        let nothing = try w.sellRoute(routeID: losing)
        #expect(nothing == 0)
        #expect(w.airline.cash == cash)
        #expect(w.routes.isEmpty)
    }

    @Test func aSharedAircraftKeepsItsOtherRoute() throws {
        var w = try Fixtures.flyingWorld()
        let first = w.routes[0].id
        let ideas = w.routeIdeas(limit: 8)
        let idea = try #require(ideas.first { !$0.stops.contains("YUB") && $0.stops.contains("YEV") })
        let second = try w.createRoute(stops: idea.stops)
        let planeID = w.aircraft[0].id
        try w.addRoute(aircraftID: planeID, routeID: second)

        try w.sellRoute(routeID: first)
        let now = w.aircraft[0].allRouteIDs
        #expect(now == [second])
        let listed = w.routes.first { $0.id == second }?.aircraftIDs ?? []
        #expect(listed == [planeID])
    }

    // MARK: Leaving an airport

    @Test func leavingAnAirportSellsItsRoutesAndPartOfTheBase() throws {
        var w = try Fixtures.flyingWorld()
        w.airline.cash = 5_000_000
        let routeID = w.routes[0].id
        establish(&w, routeIndex: 0, profitPerDay: 800)
        try w.build(.fuelDepot, at: "YUB")
        let yub = try Fixtures.airport("YUB")
        let depotPrice = w.facilityPrice(.fuelDepot, at: yub)
        let far = w.clock.minute + 10 * GameClock.minutesPerDay
        w.ops.jobs.append(Job(id: 9_001, kind: .mail, from: "YEV", to: "YUB", passengers: 0, cargoKg: 100, pay: 1_000,
                              deadlineMinute: far, expiresMinute: far, aircraftID: nil, loaded: false))

        let plan = w.leaveAirportPlan(code: "YUB")
        #expect(plan.routeIDs == [routeID])
        #expect(plan.routeSale == 800 * Tuning.routeSaleDays)
        #expect(plan.facilities == [.fuelDepot])
        #expect(plan.facilityRefund == Int((Double(depotPrice) * Tuning.leaveAirportRefundShare).rounded()))
        #expect(plan.facilityRefund < depotPrice)
        #expect(plan.jobs >= 1)

        let before = w.airline.cash
        let done = try w.leaveAirport(code: "YUB")
        #expect(done.total == plan.total)
        #expect(w.airline.cash - before == plan.total)
        #expect(w.routes.isEmpty)
        let baseLeft = w.ops.bases.contains { $0.airport == "YUB" }
        #expect(!baseLeft)
        let jobsLeft = w.ops.jobs.contains { !$0.isTaken && ($0.from == "YUB" || $0.to == "YUB") }
        #expect(!jobsLeft)
        let planeRoute = w.aircraft[0].routeID
        #expect(planeRoute == nil)
        let last = try #require(w.news.last)
        #expect(last.kind == .growth && last.subject == "left:YUB")
    }

    @Test func theHeadquartersCannotBeLeft() throws {
        var w = try Fixtures.flyingWorld()
        let problem = w.leaveAirportProblem(code: "YEV")
        #expect(problem == .isHeadquarters)
        var refused: WorldError?
        do { try w.leaveAirport(code: "YEV") } catch let error as WorldError { refused = error }
        #expect(refused == .isHeadquarters)
        #expect(w.routes.count == 1, "nothing changed")
    }

    // MARK: Moving the headquarters

    @Test func movingTheHeadquartersChargesTheFeeAndDeliveriesGoThere() throws {
        var w = try Fixtures.world()
        w.airline.cash = 50_000_000
        _ = try w.createRoute(stops: ["YEV", "YZF"])
        let tooSmall = w.headquartersProblem(to: "YZF")
        #expect(tooSmall == .levelTooLow(required: Tuning.headquartersMoveLevel))

        w.airline.level = 2
        let yzf = try Fixtures.airport("YZF")
        let fee = w.headquartersFee(to: yzf)
        #expect(fee == Int((Double(Tuning.headquartersFeePerLevel * 2) * World.sizeFactor(yzf)).rounded()))
        let options = w.headquartersOptions()
        #expect(options.contains { $0.code == "YZF" && $0.fee == fee })
        let homeOffered = options.contains { $0.code == "YEV" }
        #expect(!homeOffered)

        let before = w.airline.cash
        try w.moveHeadquarters(to: "YZF")
        #expect(w.airline.home == "YZF")
        #expect(before - w.airline.cash == fee)
        let starterAt = w.aircraft[0].location
        #expect(starterAt == "YEV", "parked aircraft stay where they are")

        w.market.listings.append(UsedListing(id: 9_999, typeID: "c208", ageYears: 15, condition: 80, price: 1_200_000, deliveryDays: 3))
        let bought = try w.buyUsed(listingID: 9_999)
        Fixtures.advance(&w, days: 10) { world in world.aircraft.first { plane in plane.id == bought }?.isDelivered == true }
        let plane = try #require(w.aircraft.first { $0.id == bought })
        #expect(plane.isDelivered)
        #expect(plane.location == "YZF")
    }

    // MARK: Trading in

    @Test func tradeInPaysTheDifference() throws {
        var w = try Fixtures.world()
        let old = w.aircraft[0]
        let value = w.saleValue(of: old)
        #expect(value > 0)
        w.market.listings.append(UsedListing(id: 9_999, typeID: "dhc6", ageYears: 20, condition: 80, price: 3_000_000, deliveryDays: 3))
        w.airline.cash = 3_000_000 - value + 10

        let newID = try w.tradeIn(aircraftID: old.id, forListing: 9_999)
        #expect(w.airline.cash == 10, "the old aircraft paid for part of the new one")
        let oldLeft = w.aircraft.contains { $0.id == old.id }
        #expect(!oldLeft)
        let bought = try #require(w.aircraft.first { $0.id == newID })
        #expect(bought.typeID == "dhc6")
    }

    @Test func tradeInForANewTypeAndRefusals() throws {
        var w = try Fixtures.world()
        let old = w.aircraft[0]
        let value = w.saleValue(of: old)
        let price = try Fixtures.type("dhc6").priceUSD
        w.airline.cash = price - value
        let newID = try w.tradeIn(aircraftID: old.id, forNewType: "dhc6")
        #expect(w.airline.cash == 0)
        #expect(w.aircraft.count == 1 && w.aircraft[0].id == newID)

        var flying = try Fixtures.flyingWorld()
        flying.airline.cash = 50_000_000
        let cash = flying.airline.cash
        let planeID = flying.aircraft[0].id
        var refused: WorldError?
        do { try flying.tradeIn(aircraftID: planeID, forNewType: "dhc6") } catch let error as WorldError { refused = error }
        #expect(refused == .aircraftHasRoute)
        #expect(flying.airline.cash == cash)
        #expect(flying.aircraft.count == 1)
    }

    // MARK: Suggested routes to bigger cities

    @Test func biggerCityIdeasStayWithinTheLevelAndUseBuyableTypes() throws {
        var w = try Fixtures.world()
        w.airline.level = 4
        let ideas = w.routeIdeas(limit: 8, focus: .biggerCities)
        print("CALIBRATION bigger-city ideas YEV level 4: " + ideas.map { "\($0.id) \($0.typeID) owned=\($0.typeOwned) \(Int($0.profitPerDay))/day" }.joined(separator: "; "))
        #expect(!ideas.isEmpty)
        let threshold = Tuning.biggerCityPopulation(level: 4)
        let fleet = Set(w.aircraft.map(\.typeID))
        let listed = Set(w.market.listings.map(\.typeID))
        for idea in ideas {
            #expect(idea.profitPerDay > 0, "\(idea.id)")
            let problem = w.routeProblem(stops: idea.stops)
            #expect(problem == nil, "\(idea.id)")
            for code in idea.stops {
                let airport = try Fixtures.airport(code)
                #expect(Progression.requiredLevel(for: airport) <= 4 || code == w.airline.home, "\(code) is open at level 4")
            }
            let farEnd = try Fixtures.airport(idea.stops[1])
            #expect(farEnd.population >= threshold, "\(idea.id)")
            let type = try Fixtures.type(idea.typeID)
            #expect(idea.typeOwned == fleet.contains(type.id), "\(idea.id)")
            if !idea.typeOwned {
                #expect(type.level <= 4, "\(idea.id)")
                #expect(type.inProduction || listed.contains(type.id), "\(idea.id)")
            }
        }
        let buyable = ideas.contains { !$0.typeOwned }
        #expect(buyable, "some ideas are for a bigger aircraft the airline could buy")

        let again = w.routeIdeas(limit: 8, focus: .biggerCities)
        #expect(again == ideas)
    }

    @Test func aBusyCityPairIsJudgedForABiggerTypeToBuy() throws {
        var w = try Fixtures.world()
        w.airline.level = 4
        let types = w.biggerIdeaTypes()
        let yeg = try Fixtures.airport("YEG")
        let yvr = try Fixtures.airport("YVR")
        let km = yeg.distanceKm(to: yvr)
        let idea = try #require(w.bestIdea(stops: ["YEG", "YVR"], km: km, types: types, inNetwork: ["YEV"]))
        let type = try Fixtures.type(idea.typeID)
        print("CALIBRATION bigger-city YEG-YVR level 4: \(idea.typeID) owned=\(idea.typeOwned) \(Int(idea.profitPerDay))/day")
        #expect(!idea.typeOwned)
        #expect(type.seats > 9, "a bigger aircraft than the Caravan: \(idea.typeID)")
    }

    @Test func aBushAirlineIsShownABiggerTypeItCouldBuy() throws {
        let w = try Fixtures.world()
        let types = w.biggerIdeaTypes().map(\.id)
        #expect(types.first == "c208", "the fleet's own type comes first")
        #expect(types.contains("dhc6"), "a Twin Otter is in production and bigger: \(types)")
        let ideas = w.routeIdeas(limit: 8, focus: .biggerCities)
        for idea in ideas {
            for code in idea.stops {
                let airport = try Fixtures.airport(code)
                #expect(Progression.requiredLevel(for: airport) <= 1 || code == w.airline.home, "\(code) is open at level 1")
            }
        }
        let strips = w.routeIdeas(limit: 5, focus: .smallStrips)
        let plain = w.routeIdeas(limit: 5)
        #expect(strips == plain, "the small-strips list is the one from before")
    }

    // MARK: Saves

    @Test func savesWithGrowthNewsLoadAndOldSavesStillDecode() throws {
        var w = try Fixtures.flyingWorld()
        w.routes[0].book = week(profitPerDay: 500)
        let routeID = w.routes[0].id
        try w.sellRoute(routeID: routeID)
        let data = try Fixtures.encode(w)
        let loaded = try JSONDecoder().decode(World.self, from: data)
        #expect(loaded.news.last?.kind == .growth)
        #expect(loaded.airline.cash == w.airline.cash)

        var old = try Fixtures.flyingWorld()
        old.operationsStore = nil
        let oldData = try Fixtures.encode(old)
        var reopened = try JSONDecoder().decode(World.self, from: oldData)
        let plan = reopened.leaveAirportPlan(code: "YUB")
        #expect(plan.routeIDs.count == 1)
        try reopened.leaveAirport(code: "YUB")
        #expect(reopened.routes.isEmpty)
    }
}
