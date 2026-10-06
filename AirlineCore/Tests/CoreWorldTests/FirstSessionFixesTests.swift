import Testing
import CoreCatalog
@testable import CoreWorld

/// Fixes from the first-session and fleet playtests: a home at a slot airport, the first-route head start, the aircraft a route
/// needs, spare aircraft that must keep a route flying, the fleet planner, aircraft away on jobs, and Relaxed starters on short strips.
@Suite struct FirstSessionFixesTests {
    /// The guide's first route from home (the best idea that starts there), else the nearest airport the starter can fly to.
    func firstRoute(_ w: World) throws -> [String] {
        let home = w.airline.home
        if let idea = w.routeIdeas(limit: 20).first(where: { $0.stops.first == home && $0.stops.count == 2 }) { return idea.stops }
        let airport = try Fixtures.airport(home)
        let near = AirportCatalog.nearest(latitude: airport.latitude, longitude: airport.longitude, limit: 40) { $0.code != home }
        for to in near {
            var copy = w
            guard let id = try? copy.createRoute(stops: [home, to.code]) else { continue }
            if copy.assignProblem(aircraftID: copy.aircraft[0].id, routeID: id) == nil { return [home, to.code] }
        }
        Testing.Issue.record("\(home): no route the starter can fly")
        return []
    }

    func caravan(_ id: Int, _ registration: String) -> Aircraft {
        Aircraft(id: id, typeID: "c208", registration: registration, builtDay: 0, condition: 90, price: 3_000_000, location: "YEV", status: .idle)
    }

    // MARK: Slots at home

    @Test func aHomeAtASlotAirportDoesNotStrandTheFirstAircraft() throws {
        for home in ["RBR", "BVB", "PHH"] {
            var w = try Fixtures.world(home: home)
            #expect(w.needsSlots(try Fixtures.airport(home)), "\(home) hands out slots")
            #expect(w.slotsHeld(at: home) == Tuning.headquartersSlots && w.slotsBought(at: home) == 0)
            w.setPausePolicy(.never)
            let stops = try firstRoute(w)
            try #require(stops.count == 2)
            let id = try w.createRoute(stops: stops)
            try w.assign(aircraftID: w.aircraft[0].id, toRoute: id)
            Fixtures.advance(&w, days: 4) { $0.airline.stats.flights >= 2 }
            print("PLAYTEST slot home \(home): \(stops.joined(separator: "-")), flights \(w.airline.stats.flights), slots scheduled \(w.slotsScheduled(at: home))")
            #expect(w.airline.stats.flights >= 1, "\(home): the starter left home")
        }
    }

    @Test func theFreeSlotsBelongToTheHeadquartersAndCannotBeSold() throws {
        var w = try Fixtures.world(home: "RBR")
        w.airline.cash = 50_000_000
        try w.buySlots(at: "RBR", count: 1)
        #expect(w.slotsHeld(at: "RBR") == Tuning.headquartersSlots + 1 && w.slotsBought(at: "RBR") == 1)
        try w.sellSlots(at: "RBR", count: 5)
        #expect(w.slotsHeld(at: "RBR") == Tuning.headquartersSlots && w.slotsBought(at: "RBR") == 0)
        var copy = w
        let sold = (try? copy.sellSlots(at: "RBR", count: 1)) != nil
        #expect(!sold, "the free slots cannot be sold")
        // A moved headquarters takes them along.
        w.airline.home = "TBT"
        #expect(w.slotsHeld(at: "RBR") == 0)
    }

    // MARK: The first-route head start

    @Test func aFirstRouteNoAircraftCanFlyDoesNotUseUpTheHeadStart() throws {
        var w = try Fixtures.world()
        // Iqaluit is in Canada and open at level 1, but far beyond a Caravan's range from Inuvik.
        let far = try w.createRoute(stops: ["YEV", "YFB"])
        let farRoute = try #require(w.routes.first { $0.id == far })
        #expect(!w.fleetCanFly(route: farRoute))
        #expect(w.opensFirstRoute)
        let good = try w.createRoute(stops: ["YEV", "YUB"])
        #expect(!w.opensFirstRoute)
        let goodRoute = try #require(w.routes.first { $0.id == good })
        #expect(goodRoute.legs.allSatisfy { $0.maturity == Tuning.firstRouteMaturity })
        let third = try w.createRoute(stops: ["YEV", "YSY"])
        let thirdRoute = try #require(w.routes.first { $0.id == third })
        #expect(thirdRoute.legs.allSatisfy { $0.maturity == Tuning.minimumMaturity })
    }

    @Test func onceARouteHasFlownTheHeadStartIsGoneForGood() throws {
        var w = try Fixtures.flyingWorld()
        Fixtures.advance(&w, days: 3) { $0.airline.stats.flights > 0 }
        try #require(w.airline.stats.flights > 0)
        for id in w.routes.map(\.id) { try w.deleteRoute(id: id) }
        #expect(!w.opensFirstRoute)
    }

    // MARK: The aircraft a route needs

    @Test func aFirstRouteItsAircraftCanFlyIsNotFlaggedShort() throws {
        var fillMore = 0
        for home in ["BET", "YEV", "ASP", "ISA", "OTZ", "DLG", "YCB", "JAV", "GOH", "PUQ", "SXM"] {
            var w = try Fixtures.world(home: home)
            let stops = try firstRoute(w)
            guard stops.count == 2 else { continue }
            let id = try w.createRoute(stops: stops)
            try w.assign(aircraftID: w.aircraft[0].id, toRoute: id)
            let route = try #require(w.routes.first { $0.id == id })
            let type = try #require(w.aircraft[0].type)
            let cycles = w.cyclesPerAircraftPerDay(route: route, type: type)
            let needed = try #require(w.aircraftNeeded(routeID: id))
            if w.demandFrequency(route: route, type: type) > cycles { fillMore += 1 }
            if route.frequency <= cycles {
                #expect(needed == 1, "\(home): one aircraft flies \(route.frequency) a day of \(cycles)")
                #expect(!w.isShortOfAircraft(routeID: id), "\(home)")
            }
            #expect((w.aircraftForDemand(routeID: id) ?? 0) >= needed, "\(home): the market figure is never below the schedule's")
        }
        print("PLAYTEST first routes where people would fill more than one aircraft: \(fillMore)")
    }

    // MARK: Spare aircraft and the fleet planner

    @Test func aSpareAircraftNeverLeavesARouteWhoseOtherAircraftCannotFly() throws {
        var w = try Fixtures.world()
        let thin = try w.createRoute(stops: ["YEV", "YUB"])
        w.aircraft.append(caravan(700, "C-FSPA"))
        for id in w.aircraft.map(\.id) { try w.assign(aircraftID: id, toRoute: thin) }
        let needed = try #require(w.aircraftNeeded(routeID: thin))
        #expect(needed == 1)
        #expect(w.spareAircraft(routeID: thin) == [700], "two aircraft where one is enough")
        // The first one goes into the hangar for a long check: the other is all the route has left.
        w.aircraft[0].status = .maintenance(until: w.clock.minute + 10 * GameClock.minutesPerDay)
        #expect(w.spareAircraft(routeID: thin).isEmpty)
        let moves = w.spareMoves(routeID: thin)
        #expect(moves.isEmpty)
    }

    @Test func aSharedAircraftCountsAsItsShare() throws {
        var w = try Fixtures.world()
        let mayo = try w.createRoute(stops: ["YEV", "YMA"])
        let tuk = try w.createRoute(stops: ["YEV", "YUB"])
        w.aircraft.append(caravan(701, "C-FSPB"))
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: mayo)
        try w.assign(aircraftID: 701, toRoute: tuk)
        try w.addRoute(aircraftID: 701, routeID: mayo)
        let mayoRoute = try #require(w.routes.first { $0.id == mayo })
        #expect(mayoRoute.aircraftIDs.count == 2)
        // Half of C-FSPB is not a whole aircraft: the dedicated one stays.
        #expect(w.spareAircraft(routeID: mayo).isEmpty)
    }

    @Test func theFleetPlannerPlacesAParkedAircraftWhereItAddsMostAndNeverMixesTypes() throws {
        var w = try Fixtures.world()
        let tuk = try w.createRoute(stops: ["YEV", "YUB"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: tuk)
        let mayo = try w.createRoute(stops: ["YEV", "YMA"])
        w.aircraft.append(caravan(702, "C-FSPC"))
        w.planFleet()
        #expect(w.aircraft.first { $0.id == 702 }?.routeID == mayo, "the empty route gains more than a second Caravan on a thin one")

        var mixed = try Fixtures.world()
        let only = try mixed.createRoute(stops: ["YEV", "YUB"])
        try mixed.assign(aircraftID: mixed.aircraft[0].id, toRoute: only)
        mixed.aircraft.append(Aircraft(id: 703, typeID: "dhc6", registration: "C-FTWO", builtDay: 0, condition: 90, price: 5_000_000,
                                       location: "YEV", status: .idle))
        mixed.planFleet()
        #expect(mixed.aircraft.first { $0.id == 703 }?.routeID == nil, "a Twin Otter is not put on a Caravan route")
    }

    // MARK: Aircraft away on a job

    @Test func anAircraftOnAJobStillBelongsToItsRoute() throws {
        var w = try Fixtures.flyingWorld()
        let routeID = w.routes[0].id
        let planeID = w.aircraft[0].id
        let far = w.clock.minute + 2 * GameClock.minutesPerDay
        w.ops.jobs.append(Job(id: 9_002, kind: .mail, from: "YEV", to: "YSY", passengers: 0, cargoKg: 50, pay: 2_000,
                              deadlineMinute: far, expiresMinute: far, aircraftID: nil, loaded: false))
        try w.takeJob(jobID: 9_002, aircraftID: planeID)
        let route = try #require(w.routes.first { $0.id == routeID })
        #expect(route.aircraftIDs.isEmpty)
        #expect(w.aircraftAwayOnJobs(routeID: routeID) == [planeID])
        #expect(w.spareAircraft(routeID: routeID).isEmpty)
    }

    // MARK: Relaxed starters

    @Test func relaxedOffersStartersThatNeedALongerRunway() throws {
        // Lukla's strip is 1,729 ft; a DC-3 needs 2,400 ft. Relaxed lets any aircraft use any land runway.
        let relaxed = World.starterOffers(home: "LUA", difficulty: .easy, mode: .easy)
        let normal = World.starterOffers(home: "LUA", difficulty: .easy, mode: .normal)
        #expect(relaxed.contains { $0.typeID == "dc3" })
        #expect(!normal.contains { $0.typeID == "dc3" })
        #expect(!relaxed.contains { $0.typeID == "c208f" }, "a floatplane still needs water")
        let w = try Fixtures.world(home: "LUA", type: "dc3", difficulty: .easy, mode: .easy)
        #expect(w.aircraft[0].typeID == "dc3")
        #expect(w.homeProblem(try Fixtures.type("dc3")) == nil, "the game agrees once it runs")
        #expect(throws: WorldError.aircraftCannotUse(airport: "LUA")) { _ = try Fixtures.world(home: "LUA", type: "dc3", difficulty: .easy, mode: .normal) }
    }

    @Test func theNextStepSuggestsAircraftByTheGamesOwnRunwayRule() throws {
        let listing = UsedListing(id: 1, typeID: "dc3", ageYears: 40, condition: 70, price: 500_000, deliveryDays: 3)
        var relaxed = try Fixtures.world(home: "LUA", difficulty: .easy, mode: .easy)
        relaxed.market.listings = [listing]
        var normal = try Fixtures.world(home: "LUA", difficulty: .easy, mode: .normal)
        normal.market.listings = [listing]
        #expect(relaxed.aircraftStep() == .buyAircraft(typeID: "dc3", price: 500_000))
        #expect(normal.aircraftStep() == nil)
    }
}
