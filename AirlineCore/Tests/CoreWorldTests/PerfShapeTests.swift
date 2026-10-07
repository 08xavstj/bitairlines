import Testing
import CoreCatalog
@testable import CoreWorld

/// The shape of the slow paths: the quick ferry search gives the same plans as the plain one, a goal nobody can reach is answered
/// fast, and hub matching stays quick on a big hub. Prints PLAYTEST lines with timings; the bounds are generous so CI noise never
/// fails a build, but a return to the old cost (seconds) would.
@Suite struct PerfShapeTests {
    /// A world with one aircraft of several short-range types parked at Inuvik. Returns the world and their indexes.
    static func ferryWorld(mode: GameMode = .normal) throws -> (World, [Int]) {
        var w = try Fixtures.world(mode: mode)
        var indexes: [Int] = []
        for (n, typeID) in ["c208", "dhc2", "dhc6", "dc3", "dhc2f"].enumerated() where AircraftCatalog.type(typeID) != nil {
            w.aircraft.append(Aircraft(id: 700 + n, typeID: typeID, registration: "C-PF\(n)", builtDay: 0, condition: 100, price: 100_000,
                                       location: "YEV", status: .idle))
            indexes.append(w.aircraft.count - 1)
        }
        return (w, indexes)
    }

    /// Start and goal airports spread over the whole map, the same every run.
    static func pairs(count: Int) -> [(String, String)] {
        let grid = FerryGrid.airports
        return (0..<count).map { q in (grid[(q * 97 + 11) % grid.count].code, grid[(q * 389 + 503) % grid.count].code) }
    }

    @Test func theQuickFerrySearchGivesTheSamePlansAsThePlainOne() throws {
        for mode in [GameMode.normal, .realism] {
            let (w, indexes) = try Self.ferryWorld(mode: mode)
            var compared = 0
            var noWay = 0
            for i in indexes {
                for (start, goal) in Self.pairs(count: 8) + [("YEV", "HNL"), ("YEV", "YZF"), ("YEV", "YEG")] {
                    let quick = w.ferryPlan(aircraftIndex: i, from: start, toAny: [goal])
                    let plain = w.ferryPlan(aircraftIndex: i, from: start, toAny: [goal], fast: false)
                    #expect(quick == plain, "\(w.aircraft[i].typeID) \(start) to \(goal) in \(mode)")
                    compared += 1
                    if plain == nil { noWay += 1 }
                }
            }
            // Several goals at once: the first one reached wins, the same way in both.
            let i = indexes[0]
            let quick = w.ferryPlan(aircraftIndex: i, from: "YEV", toAny: ["HNL", "YZF", "YEG"])
            let plain = w.ferryPlan(aircraftIndex: i, from: "YEV", toAny: ["HNL", "YZF", "YEG"], fast: false)
            #expect(quick == plain)
            print("PLAYTEST ferry quick vs plain (\(mode)): \(compared) questions, \(noWay) with no way there, all the same")
        }
    }

    @Test func aGoalNobodyCanReachIsAnsweredQuickly() throws {
        let (w, indexes) = try Self.ferryWorld()
        let caravan = indexes[0]
        let clock = ContinuousClock()
        var quick: FerryPlan?
        let quickTime = clock.measure {
            for _ in 0..<20 { quick = w.ferryPlan(aircraftIndex: caravan, from: "YEV", toAny: ["HNL"]) }
        }
        var plain: FerryPlan?
        let plainTime = clock.measure { plain = w.ferryPlan(aircraftIndex: caravan, from: "YEV", toAny: ["HNL"], fast: false) }
        #expect(quick == nil && plain == nil, "Hawaii is out of a Caravan's reach from the Arctic")
        // A far goal that can be reached, through many stops.
        var far: FerryPlan?
        let farTime = clock.measure { far = w.ferryPlan(aircraftIndex: caravan, from: "YEV", toAny: ["LHR"]) }
        #expect(far.map { $0.stopsOnTheWay >= 1 } ?? true)
        print("PLAYTEST ferry no way there (Caravan YEV to HNL): 20 quick searches \(quickTime), one plain search \(plainTime)")
        print("PLAYTEST ferry far (Caravan YEV to LHR): \(farTime), \(far?.hops.count ?? 0) hops")
        #expect(quickTime < .seconds(3))
        #expect(farTime < .seconds(3))
    }

    /// A level 7 airline with a hub terminal at Inuvik and a route from it to each of the 40 nearest map airports.
    static func hubWorld(spokes: Int = 40) throws -> World {
        var w = try Fixtures.world()
        w.airline.level = 7
        let home = try Fixtures.airport("YEV")
        let near = FerryGrid.airports.filter { $0.code != "YEV" }.sorted { home.distanceKm(to: $0) < home.distanceKm(to: $1) }.prefix(spokes)
        for airport in Array(near) + [home] where !w.airline.permits.contains(airport.country) { w.airline.permits.append(airport.country) }
        for airport in near { _ = try w.createRoute(stops: ["YEV", airport.code]) }
        w.ops.bases.append(Base(airport: "YEV", facilities: [.hubTerminal], openedDay: 0))
        return w
    }

    @Test func hubPairsAreGroupedTheSameWayAsBeforeAndQuickly() throws {
        var w = try Self.hubWorld()
        let paths = w.connectionPaths()
        #expect(paths.count > 100)
        let grouped = World.pathsByPair(paths)
        // The old way: each pair once, in key order, with its paths found by a filter over all of them.
        var keys: [String] = []
        for path in paths where !keys.contains(path.pairKey) { keys.append(path.pairKey) }
        let old = keys.sorted().map { key in (key: key, paths: paths.filter { $0.pairKey == key }) }
        #expect(grouped.map { $0.key } == old.map { $0.key })
        #expect(grouped.map { $0.paths } == old.map { $0.paths })
        let clock = ContinuousClock()
        let time = clock.measure { w.refreshConnections() }
        let through = w.routes.reduce(0.0) { sum, route in sum + route.legs.reduce(0.0) { $0 + $1.connectingPaxPerDay } }
        #expect(through > 0)
        print("PLAYTEST hub matching: \(w.routes.count) spokes, \(paths.count) paths, \(grouped.count) pairs, refresh \(time)")
        #expect(time < .seconds(3))
    }

    @Test func anAircraftThatCannotTakeOffWhereItStandsIsToldSoBeforeAnySearch() throws {
        let (w, indexes) = try Self.ferryWorld()
        // The Beaver floatplane stands on Inuvik's runway: it can never leave, so the reason is the airport, not "too far".
        let floats = try #require(indexes.first { w.aircraft[$0].typeID == "dhc2f" })
        let way = w.positioning(aircraftIndex: floats, toAny: ["YZF"])
        #expect(way.plan == nil)
        #expect(way.problem == WorldError.aircraftCannotUse(airport: "YEV"))
        #expect(w.positioningProblem(aircraftIndex: floats, toAny: ["YEV"]) == nil, "it is there already")
        // A wheeled aircraft at a stop of the route has nothing to fly and no problem, and the plan shown is the one flown.
        let caravan = indexes[0]
        let there = w.positioning(aircraftIndex: caravan, toAny: ["YUB", "YEV"])
        #expect(there.problem == nil)
        #expect(there.plan?.hops.isEmpty == true)
        #expect(there.plan == w.ferryPlan(aircraftID: w.aircraft[caravan].id, toAny: ["YUB", "YEV"]))
        let away = w.positioning(aircraftIndex: caravan, toAny: ["YZF", "YUB"])
        #expect(away.problem == nil)
        #expect(away.plan?.destination == "YUB", "the nearest goal it can use, as startFerry flies it")
        #expect(away.plan == w.ferryPlan(aircraftID: w.aircraft[caravan].id, toAny: ["YZF", "YUB"]))
    }

    @Test func oneAircraftWeighedForARouteMatchesTheChecksAndTheFerry() throws {
        var w = try Self.hubWorld(spokes: 12)
        for (n, airport) in FerryGrid.airports.enumerated() where n % 150 == 0 {
            w.aircraft.append(Aircraft(id: 800 + n, typeID: "c208", registration: "C-PC\(n)", builtDay: 0, condition: 100, price: 100_000,
                                       location: airport.code, status: .idle))
        }
        let clock = ContinuousClock()
        var checked = 0
        let time = clock.measure {
            for route in w.routes {
                for plane in w.aircraft {
                    let choice = w.planeChoice(aircraftID: plane.id, routeID: route.id)
                    let problem = w.assignProblem(aircraftID: plane.id, routeID: route.id)
                    #expect(choice.problem == problem)
                    #expect(choice.ferry == (problem == nil ? w.ferryPlan(aircraftID: plane.id, toAny: route.stops) : nil))
                    checked += 1
                }
            }
        }
        print("PLAYTEST plane choices: \(checked) aircraft and route pairs checked in \(time)")
        #expect(time < .seconds(20))
    }
}
