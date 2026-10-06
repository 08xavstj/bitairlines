import Testing
import CoreCatalog
@testable import CoreWorld

/// Empty positioning flights that need stops on the way (FerryPlan.swift), and the checks that use them.
@Suite struct FerryPlanTests {
    /// A Beaver (750 km range) parked at Inuvik, next to the starter Caravan. Returns the world and the Beaver's index.
    static func beaverWorld() throws -> (World, Int) {
        var w = try Fixtures.world()
        w.setPausePolicy(.never)
        w.aircraft.append(Aircraft(id: 501, typeID: "dhc2", registration: "C-FBVR", builtDay: 0, condition: 100, price: 150_000,
                                   location: "YEV", status: .idle))
        return (w, w.aircraft.count - 1)
    }

    static func job(_ w: World, from: String, to: String) -> Job {
        Job(id: 9_001, kind: .crewChange, from: from, to: to, passengers: 2, cargoKg: 0, pay: 8_000,
            deadlineMinute: w.clock.minute + 10 * 1440, expiresMinute: w.clock.minute + 2 * 1440, aircraftID: nil, loaded: false)
    }

    /// Every hop of a plan is within the aircraft's range, and the plan ends where it was asked to.
    static func checkHops(_ plan: FerryPlan, from start: String, to end: String, rangeKm: Int) throws {
        #expect(plan.from == start)
        #expect(plan.hops.last == end)
        var here = try Fixtures.airport(start)
        for code in plan.hops {
            let next = try Fixtures.airport(code)
            #expect(here.distanceKm(to: next) <= Double(rangeKm), "\(here.code) to \(code)")
            here = next
        }
    }

    @Test func aFarFerryIsPlannedThroughStops() throws {
        let made = try Self.beaverWorld()
        let w = made.0
        let yev = try Fixtures.airport("YEV")
        let yzf = try Fixtures.airport("YZF")
        #expect(yev.distanceKm(to: yzf) > 750, "Yellowknife is out of a Beaver's direct range from Inuvik")
        let plan = try #require(w.ferryPlan(aircraftID: 501, toAny: ["YZF"]))
        #expect(plan.stopsOnTheWay >= 1)
        try Self.checkHops(plan, from: "YEV", to: "YZF", rangeKm: 750)
        #expect(plan.km >= yev.distanceKm(to: yzf))
        #expect(plan.hours > 0)
        // The same question gives the same answer.
        let again = w.ferryPlan(aircraftID: 501, toAny: ["YZF"])
        #expect(again == plan)
        // A direct hop stays direct.
        let near = try #require(w.ferryPlan(aircraftID: 501, toAny: ["YUB"]))
        #expect(near.hops == ["YUB"])
    }

    @Test func aFreeAircraftFliesTheStopsOneAfterAnother() throws {
        let made = try Self.beaverWorld()
        var w = made.0
        let i = made.1
        let plan = try #require(w.ferryPlan(aircraftID: 501, toAny: ["YZF"]))
        let started = w.startFerry(index: i, to: "YZF")
        #expect(started)
        #expect(w.aircraft[i].flight?.to == plan.hops.first)
        #expect(w.aircraft[i].ferryTargetStore == "YZF")
        var landed: [String] = ["YEV"]
        for _ in 0..<(3 * 48) {
            w.advance(byMinutes: 30)
            if landed.last != w.aircraft[i].location { landed.append(w.aircraft[i].location) }
            if w.aircraft[i].location == "YZF", case .idle = w.aircraft[i].status { break }
        }
        #expect(Array(landed.dropFirst()) == plan.hops)
        #expect(w.aircraft[i].location == "YZF")
        #expect(w.aircraft[i].status == .idle)
        #expect(w.aircraft[i].ferryTargetStore == nil)
    }

    @Test func aJobWhosePickupIsOutOfDirectRangeCanBeTakenAndTheAircraftGetsThere() throws {
        var w = try Fixtures.world()
        w.setPausePolicy(.never)
        let plane = w.aircraft[0].id
        let range = try #require(w.aircraft[0].type?.rangeKm)
        let yev = try Fixtures.airport("YEV")
        let yeg = try Fixtures.airport("YEG")
        #expect(yev.distanceKm(to: yeg) > Double(range), "Edmonton is out of the Caravan's direct range from Inuvik")
        w.ops.jobs.append(Self.job(w, from: "YEG", to: "YMM"))
        let problem = w.jobProblem(jobID: 9_001, aircraftID: plane)
        #expect(problem == nil)
        #expect(w.flyableAircraft(forJob: 9_001).contains(plane))
        let choice = try #require(w.planeChoices(forJob: 9_001).first)
        #expect(choice.aircraftID == plane && choice.canDo)
        let ferry = try #require(choice.ferry)
        #expect(ferry.stopsOnTheWay >= 1)
        try Self.checkHops(ferry, from: "YEV", to: "YEG", rangeKm: range)

        try w.takeJob(jobID: 9_001, aircraftID: plane)
        var reachedPickup = false
        for _ in 0..<(4 * 48) {
            w.advance(byMinutes: 30)
            if w.aircraft[0].location == "YEG" { reachedPickup = true }
            if reachedPickup { break }
        }
        #expect(reachedPickup)
        #expect(w.aircraft[0].jobID == 9_001 || w.ops.jobsDone.contains(where: { $0.to == "YMM" }))
    }

    @Test func noWayThereIsStillOutOfRange() throws {
        var w = try Fixtures.world()
        let plane = w.aircraft[0].id
        // Hawaii: the leg between the islands is short, but no chain of stops a Caravan can fly reaches it from the Arctic.
        #expect(w.ferryPlan(aircraftID: plane, toAny: ["HNL"]) == nil)
        w.ops.jobs.append(Self.job(w, from: "HNL", to: "MUE"))
        let problem = w.jobProblem(jobID: 9_001, aircraftID: plane)
        guard case .some(.outOfRange) = problem else {
            Testing.Issue.record("expected out of range, got \(String(describing: problem))")
            return
        }
        var copy = w
        var refused = false
        do { try copy.takeJob(jobID: 9_001, aircraftID: plane) } catch { refused = true }
        #expect(refused)
        #expect(w.flyableAircraft(forJob: 9_001).isEmpty)
    }

    @Test func anAircraftFarFromItsRouteIsAssignedAndFliesThereThroughStops() throws {
        var w = try Fixtures.world()
        w.setPausePolicy(.never)
        let plane = w.aircraft[0].id
        w.aircraft[0].location = "YEG"
        let route = try w.createRoute(stops: ["YEV", "YUB"])
        let problem = w.assignProblem(aircraftID: plane, routeID: route)
        #expect(problem == nil)
        try w.assign(aircraftID: plane, toRoute: route)
        #expect(w.aircraft[0].routeID == route)
        #expect(w.aircraft[0].flight?.isFerry == true)
        #expect(w.aircraft[0].flight?.to != "YEV" && w.aircraft[0].flight?.to != "YUB", "the first hop is a stop on the way")
        var onRoute = false
        for _ in 0..<(4 * 48) {
            w.advance(byMinutes: 30)
            if w.aircraft[0].location == "YEV" || w.aircraft[0].location == "YUB" { onRoute = true }
            if onRoute { break }
        }
        #expect(onRoute)
        #expect(w.aircraft[0].routeID == route)
    }

    @Test func thePlannerFindsALegNoAircraftCanFly() throws {
        let w = try Fixtures.world()
        let plane = w.aircraft[0].id
        let short = w.plannerCheck(stops: ["YEV", "YUB"])
        #expect(short.fits && short.fittingAircraftIDs == [plane])
        #expect(w.fleetCanFly(from: "YEV", to: "YUB"))
        #expect(!w.fleetCanFly(from: "YEV", to: "YEG"))
        let far = w.plannerCheck(stops: ["YEV", "YEG"])
        #expect(!far.fits)
        #expect(far.blockedLeg == 0)
        guard case .some(.outOfRange) = far.blockedProblem else {
            Testing.Issue.record("expected out of range, got \(String(describing: far.blockedProblem))")
            return
        }
        if let stop = far.suggestedStop {
            let rangeKm = try #require(w.aircraft[0].type?.rangeKm)
            let range = Double(rangeKm)
            let between = try Fixtures.airport(stop)
            let yev = try Fixtures.airport("YEV")
            let yeg = try Fixtures.airport("YEG")
            #expect(yev.distanceKm(to: between) <= range)
            #expect(between.distanceKm(to: yeg) <= range)
        }
    }
}
