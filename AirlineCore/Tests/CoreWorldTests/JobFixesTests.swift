import Testing
import CoreCatalog
@testable import CoreWorld

/// Jobs after the playtest: an aircraft goes back to every route it flew, dropping a job skips no repair, a job that can never be
/// flown is given back, special jobs stay on the board, slot airports and the Realism fuel rule count, and loads fit an aircraft
/// that can fly them (JobFlights.swift, JobFit.swift, Jobs.swift).
@Suite struct JobFixesTests {
    func job(_ w: World, id: Int = 900, from: String = "YEV", to: String = "YUB", passengers: Int = 4) -> Job {
        Job(id: id, kind: .crewChange, from: from, to: to, passengers: passengers, cargoKg: 0, pay: 6_000,
            deadlineMinute: w.clock.minute + 2 * 1440, expiresMinute: w.clock.minute + 1440, aircraftID: nil, loaded: false)
    }

    /// The error a throwing call gave, if any (kept out of #expect so no mutating call runs inside a macro).
    static func error(_ body: () throws -> Void) -> WorldError? {
        do {
            try body()
            return nil
        } catch let error as WorldError {
            return error
        } catch {
            return .invalidChoice
        }
    }

    @Test func aSharedAircraftKeepsItsOtherRoutesWhenItsMainRouteClosesDuringAJob() throws {
        var w = try Fixtures.world()
        w.setPausePolicy(.never)
        for code in ["YEV", "YUB", "YSY"] { Fixtures.light(&w, code) }
        let plane = w.aircraft[0].id
        let north = try w.createRoute(stops: ["YEV", "YUB"])
        let east = try w.createRoute(stops: ["YEV", "YSY"])
        let coast = try w.createRoute(stops: ["YUB", "YSY"])
        try w.assign(aircraftID: plane, toRoute: north)
        try w.addRoute(aircraftID: plane, routeID: east)
        try w.addRoute(aircraftID: plane, routeID: coast)
        w.ops.jobs.append(job(w))
        try w.takeJob(jobID: 900, aircraftID: plane)
        try w.deleteRoute(id: north)
        Fixtures.advance(&w, days: 5) { $0.ops.jobsDone.count == 1 }
        #expect(w.ops.jobsDone.count == 1)
        // The order changes as it flies (it takes whichever route leaves first), so compare the set.
        let flown = w.aircraft[0].allRouteIDs
        #expect(flown.count == 2 && Set(flown) == Set([east, coast]), "back on the two routes that are left")
        let listed = SharedAircraftTests.consistent(w)
        #expect(listed)
    }

    @Test func droppingAJobDoesNotSkipARepairOrACheck() throws {
        var w = try Fixtures.flyingWorld()
        let plane = w.aircraft[0].id
        let route = try #require(w.aircraft[0].routeID)
        let type = try #require(w.aircraft[0].type)
        w.ops.jobs.append(job(w))
        try w.takeJob(jobID: 900, aircraftID: plane)
        w.raiseBreakdown(aircraftIndex: 0, type: type)
        let grounded = w.aircraft[0].status
        try w.dropJob(jobID: 900)
        #expect(w.aircraft[0].status == grounded, "still waiting for its repair")
        #expect(w.aircraft[0].jobID == nil && w.aircraft[0].routeID == route, "back on its route for when it is fixed")
        let listed = SharedAircraftTests.consistent(w)
        #expect(listed)

        var h = try Fixtures.flyingWorld()
        h.ops.jobs.append(job(h))
        try h.takeJob(jobID: 900, aircraftID: plane)
        let until = h.clock.minute + 3 * 1440
        h.aircraft[0].status = .maintenance(until: until)
        try h.dropJob(jobID: 900)
        #expect(h.aircraft[0].status == .maintenance(until: until), "the check is not cut short")
        #expect(h.aircraft[0].routeID == route)
    }

    @Test func aKitCannotComeOffWhileTheAircraftIsOnAJob() throws {
        var w = try Fixtures.world()
        let plane = w.aircraft[0].id
        w.aircraft[0].kits = [.stolKit]
        w.ops.jobs.append(job(w))
        try w.takeJob(jobID: 900, aircraftID: plane)
        let refused = Self.error { try w.remove(.stolKit, aircraftID: plane) }
        #expect(refused == .aircraftBusy)
        #expect(w.aircraft[0].kits == [.stolKit])
    }

    @Test func anAircraftThatCanNoLongerUseAJobAirportGivesTheJobBack() throws {
        var w = try Fixtures.flyingWorld()
        let plane = w.aircraft[0].id
        w.ops.jobs.append(job(w))
        try w.takeJob(jobID: 900, aircraftID: plane)
        // Floats on: it can never use the runways at either end again (as when a kit comes off or a runway extension goes).
        w.aircraft[0].kits = [.floats]
        w.aircraft[0].status = .boarding(until: w.clock.minute)
        w.depart(0)
        #expect(w.aircraft[0].jobID == nil)
        #expect(w.aircraft[0].flight == nil, "it does not take off")
        let back = w.ops.jobs.first { $0.id == 900 }
        #expect(back != nil && back?.aircraftID == nil, "the offer is back on the board")
        let note = try #require(w.news.last)
        #expect(note.kind == .milestone && note.subject == "jobgone:\(w.aircraft[0].registration):YUB")
        #expect(note.amount == JobGiveUpReason.cannotUseAirport.rawValue)
    }

    @Test func aDroppedDispatchGoesBackOnTheBoardAtNoCost() throws {
        var w = try Fixtures.flyingWorld()
        w.setRealDay(RealCalendarTests.day)
        let dispatch = try #require(w.dispatchToday)
        let plane = try #require(w.flyableAircraft(forJob: dispatch.id).first)
        try w.takeJob(jobID: dispatch.id, aircraftID: plane)
        let reputation = w.airline.reputation
        try w.dropJob(jobID: dispatch.id)
        let again = try #require(w.dispatchToday)
        #expect(again.id == dispatch.id && !again.isTaken, "still today's dispatch, for another aircraft")
        #expect(w.airline.reputation == reputation)
        #expect(w.aircraft[0].jobID == nil)
        #expect(!w.dispatchStampedToday)
    }

    @Test func aJobFromABusyAirportNeedsSlotsThere() throws {
        var w = try Fixtures.world()
        w.setPausePolicy(.never)
        let plane = w.aircraft[0].id
        let yeg = try Fixtures.airport("YEG")
        #expect(w.needsSlots(yeg) && w.slotsHeld(at: "YEG") == 0)
        w.ops.jobs.append(job(w, from: "YEG", to: "YMM"))
        let offered = w.ops.jobs[0]
        #expect(!w.isOnOffer(offered))
        #expect(w.jobProblem(jobID: 900, aircraftID: plane) == .jobUnavailable, "nothing may leave Edmonton without a slot")
        w.ops.slots.append(SlotHolding(airport: "YEG", daily: 2))
        #expect(w.isOnOffer(offered))
        #expect(w.jobProblem(jobID: 900, aircraftID: plane) == nil)

        // New offers never start at a slot airport where the airline holds no slots.
        var fresh = try Fixtures.world()
        fresh.ops.jobArea = ["YEG", "YMM", "YOJ", "YZF"]
        var made: [Job] = []
        for _ in 0..<6 {
            for kind in [JobKind.mail, .fuelDrums, .crewChange, .lodgeCharter, .freight, .survey] {
                if let job = fresh.makeJob(kind: kind) { made.append(job) }
            }
        }
        #expect(!made.isEmpty)
        #expect(made.allSatisfy { $0.from != "YEG" })
    }

    @Test func realismJobsKeepTheFuelRule() throws {
        var w = try Fixtures.world(home: "TBT", type: "c208", mode: .realism)
        w.aircraft.append(Aircraft(id: 77, typeID: "dhc2", registration: "PP-BVR", builtDay: 0, condition: 90, price: 300_000,
                                   location: "TBT", status: .idle))
        // Olivenca and Novo Campo sell no fuel: Tabatinga to Olivenca, the job, and back is more than a Beaver's 750 km.
        w.ops.jobs.append(job(w, from: "OLC", to: "BCR", passengers: 2))
        let dry = w.jobProblem(jobID: 900, aircraftID: 77)
        guard case .some(.noFuel) = dry else {
            Testing.Issue.record("expected no fuel, got \(String(describing: dry))")
            return
        }
        // From Tabatinga, which sells fuel, a short job and back is fine.
        w.ops.jobs.append(job(w, id: 901, from: "TBT", to: "OLC", passengers: 2))
        #expect(w.jobProblem(jobID: 901, aircraftID: 77) == nil)

        // The same long job outside Realism has no fuel rule.
        var normal = try Fixtures.world(home: "TBT", type: "c208")
        normal.aircraft.append(Aircraft(id: 77, typeID: "dhc2", registration: "PP-BVR", builtDay: 0, condition: 90, price: 300_000,
                                        location: "TBT", status: .idle))
        normal.ops.jobs.append(job(normal, from: "OLC", to: "BCR", passengers: 2))
        #expect(normal.jobProblem(jobID: 900, aircraftID: 77) == nil)
    }

    @Test func jobsAreSizedToAnAircraftThatCanFlyThem() throws {
        var w = try Fixtures.world()
        // A bigger aircraft still on order does not count: an evacuation asks for what the Caravan can carry.
        w.aircraft.append(Aircraft(id: 78, typeID: "dc3", registration: "C-FDCT", builtDay: 0, condition: 90, price: 500_000,
                                   location: "YEV", status: .onOrder(until: w.clock.minute + 30 * 1440)))
        let seats = try #require(w.aircraft[0].type?.seats)
        #expect(w.biggestSeats() == seats)
        w.startEvent(.forestFire, at: "YUB")
        let evacuations = w.ops.jobs.filter { $0.kind == .evacuation }
        #expect(!evacuations.isEmpty)
        for job in evacuations {
            #expect(job.passengers <= seats)
            #expect(w.jobCanBeFlown(job), "\(job.from) to \(job.to)")
        }
    }
}
