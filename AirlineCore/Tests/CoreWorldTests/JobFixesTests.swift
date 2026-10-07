import Testing
import CoreCatalog
@testable import CoreWorld

/// Jobs and the real calendar after the playtest: an aircraft goes back to every route it flew, dropping a job skips no repair,
/// a job that can never be flown is given back, special jobs stay on the board, slot airports and the Realism fuel rule count,
/// loads fit an aircraft that can fly them, job legs wait at the same gate as route legs, the real calendar only moves forward,
/// stamps count in any order, event jobs count after the end, goals are sized by what lands and can be doubled a week late
/// (JobFlights.swift, JobFit.swift, Jobs.swift, DailyDispatch.swift, SeasonalEvents.swift, RealDay.swift, WeeklyGoals.swift).
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

    // MARK: Routes and status around a job

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

    @Test func droppingAnOrdinaryJobCostsTheTunedReputation() throws {
        var w = try Fixtures.world()
        let plane = w.aircraft[0].id
        w.ops.jobs.append(job(w))
        try w.takeJob(jobID: 900, aircraftID: plane)
        let reputation = w.airline.reputation
        try w.dropJob(jobID: 900)
        #expect(w.airline.reputation == max(0, reputation - Tuning.reputationPerDroppedJob))
        #expect(w.ops.jobs.isEmpty)
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

    @Test func aJobLegWaitsForWeatherAtTheSameGateAsARouteLeg() throws {
        var w = try Fixtures.flyingWorld()
        let plane = w.aircraft[0].id
        w.ops.jobs.append(job(w))
        try w.takeJob(jobID: 900, aircraftID: plane)
        let until = w.clock.minute + 2 * 1440
        w.market.closures.append(Closure(airport: "YUB", untilMinute: until))
        w.aircraft[0].status = .boarding(until: w.clock.minute)
        w.depart(0)
        #expect(w.aircraft[0].status == .boarding(until: until), "held at the gate until the weather clears")
        #expect(w.aircraft[0].flight == nil && w.aircraft[0].jobID == 900)
        #expect(w.ops.jobs.first { $0.id == 900 }?.loaded == false)
    }

    // MARK: Special jobs and the board

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
        w.aircraft[0].location = "YEG"
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

    @Test func aMedevacStaysOnOfferTwelveHoursAndMakesTheNews() throws {
        var w = try Fixtures.world()
        var medevac: Job?
        for _ in 0..<20 where medevac == nil { medevac = w.makeJob(kind: .medevac) }
        let job = try #require(medevac)
        #expect(job.expiresMinute - w.clock.minute == Tuning.medevacOfferHours * 60)
        let from = try Fixtures.airport(job.from)
        let to = try Fixtures.airport(job.to)
        let hoursToFly = from.distanceKm(to: to) / 300.0 + 1.0
        #expect(job.deadlineMinute >= w.clock.minute + Int((hoursToFly + Double(Tuning.medevacOfferHours)) * 60))
        #expect(job.deadlineMinute > job.expiresMinute)

        // Posted by the daily board: the news says one is up.
        for _ in 0..<30 where !w.ops.jobs.contains(where: { $0.kind == .medevac }) {
            w.ops.jobs = []
            w.dailyJobs()
        }
        let posted = w.ops.jobs.filter { $0.kind == .medevac }
        try #require(!posted.isEmpty)
        for job in posted {
            #expect(w.news.contains { $0.kind == .milestone && $0.subject == "medevac:\(job.from):\(job.to)" && $0.amount == job.pay })
        }
    }

    @Test func everyStartHasAJobAreaAndPuntaArenasGetsItsDispatch() throws {
        for region in StartRegions.all {
            for home in region.headquarters {
                var made: World?
                for offer in World.starterOffers(home: home, difficulty: .standard) where made == nil {
                    let config = NewGameConfig(airlineName: "Lontra Air", airlineCode: "LT", homeAirport: home, branding: .starter,
                                               difficulty: .standard, starterTypeID: offer.typeID, seed: 3, mode: .normal)
                    made = try? World.newGame(config)
                }
                let w = try #require(made, "\(home) has no starter")
                #expect(w.ops.jobArea.count >= 2, "\(home): jobs need a pair of airports")
            }
        }
        // Every strip near Punta Arenas is in Argentina: one-off jobs reach across the border, so the board and the dispatch work.
        let puq = try Fixtures.world(home: "PUQ")
        #expect(puq.ops.jobArea.count >= Tuning.jobAreaMinimumAirports)
        #expect(puq.ops.jobArea.contains { AirportCatalog.airport($0)?.country == "AR" })
        #expect(puq.dispatchPlan(realDay: RealCalendarTests.day) != nil)
    }

    // MARK: The real calendar

    @Test func theRealCalendarOnlyMovesForward() throws {
        var w = try Fixtures.flyingWorld()
        let day = RealCalendarTests.day
        w.setRealDay(day)
        let dispatch = try #require(w.dispatchToday)
        let goal = try #require(w.ops.realWeekGoal)
        w.ops.realWeekGoal?.done = true
        // The phone's clock set back a day (or a flight west across midnight): nothing is posted or re-armed.
        w.setRealDay(day - 1)
        #expect(w.realDay == day)
        #expect(w.dispatchToday?.id == dispatch.id)
        #expect(w.ops.jobs.filter { $0.dispatchDay != nil }.count == 1)
        #expect(w.ops.realWeekGoal?.week == goal.week && w.ops.realWeekGoal?.done == true, "a met goal stays met")
        // Capped rewards count against the latest day seen, so a day's caps never open again.
        #expect(w.rewardDay(day - 1) == day)
        #expect(w.rewardDay(day + 1) == day + 1)
        // A day whose dispatch was flown never gets a second one, even when the board is worked out again.
        w.noteSpecialJobDone(dispatch)
        let flownID = dispatch.id
        w.ops.jobs.removeAll { $0.id == flownID }
        w.ops.dispatch.postedDay = 0
        w.setRealDay(day)
        #expect(w.dispatchToday == nil && w.dispatchStampedToday)
    }

    @Test func stampsCountInAnyOrder() throws {
        var w = try Fixtures.flyingWorld()
        let day = RealCalendarTests.day
        w.earnStamp(day: day + 1)
        w.earnStamp(day: day)
        w.earnStamp(day: day)
        #expect(w.ops.dispatch.stamps == 2, "yesterday's dispatch landing after today's still counts, once")
        #expect(w.ops.dispatch.isStamped(day) && w.ops.dispatch.isStamped(day + 1) && !w.ops.dispatch.isStamped(day + 2))
        #expect(w.ops.dispatch.lastStampDay == day + 1)
    }

    @Test func anEventJobTakenBeforeTheEndStillCountsWhenItLandsAfter() throws {
        var w = try Fixtures.flyingWorld()
        w.setRealDay(RealCalendar.realDay(year: 2026, month: 12, day: 10))
        #expect(w.activeSeason?.kind == .holidayParcels)
        w.countSeasonJob(.holidayParcels)
        w.countSeasonJob(.holidayParcels)
        w.setRealDay(RealCalendar.realDay(year: 2026, month: 12, day: 24))
        #expect(w.activeSeason == nil)
        #expect(w.ops.season.ended == .holidayParcels && w.ops.season.endedJobsDone == 2)
        w.countSeasonJob(.holidayParcels)
        #expect(w.ops.unlockedLiveries.contains(UnlockableLiveries.seasonCode(.holidayParcels)), "the third job landed after the end")
    }

    // MARK: Goals

    @Test func aGoalMetLateOnSundayCanStillBeDoubledTheNextWeek() throws {
        var w = try Fixtures.world()
        let first = try #require(w.ops.weeklyGoal)
        #expect(w.goalToDouble == nil)
        w.ops.weeklyGoal?.done = true
        w.startWeeklyGoal(week: first.week + 1)
        let second = try #require(w.ops.weeklyGoal)
        #expect(!second.done && second.previousMetWeek == first.week && second.previousMetReward == first.reward)
        let paid = try #require(w.goalToDouble)
        #expect(paid.week == first.week && paid.reward == first.reward)
        w.ops.weeklyGoal?.done = true
        #expect(w.goalToDouble?.week == second.week, "this week's goal takes over once it is met")
    }

    @Test func aPlaceGoalIsSizedByWhatReallyLandsThere() throws {
        var w = try Fixtures.flyingWorld()
        w.startWeeklyGoal(week: 4)
        #expect(w.ops.weeklyGoal?.place == "YUB" && w.ops.weeklyGoal?.kind == .passengers)
        let toVillage = Flight(from: "YEV", to: "YUB", departedMinute: 0, distanceKm: 140, passengers: 100, cargoKg: 3_000, revenue: 0, cost: 0, isFerry: false)
        let toTown = Flight(from: "YUB", to: "YEV", departedMinute: 0, distanceKm: 140, passengers: 500, cargoKg: 20_000, revenue: 0, cost: 0, isFerry: false)
        w.countGoalArrival(toVillage)
        w.countGoalArrival(toTown)
        w.countGoalArrival(toTown)
        #expect(w.ops.weeklyGoal?.arrivals(.freightKg, at: "YUB") == 3_000)
        #expect(w.ops.weeklyGoal?.arrivals(.passengers, at: "YEV") == 1_000)
        #expect(w.ops.weeklyGoal?.done == true, "met during the week, not at the next midnight")

        // Next week's freight goal at the village asks for what landed there plus the stretch, not a share of the airline's total.
        w.startWeeklyGoal(week: 5)
        let goal = try #require(w.ops.weeklyGoal)
        #expect(goal.kind == .freightKg && goal.place == "YUB")
        #expect(goal.target == 3_300)
        #expect(goal.lastWeekArrivals(.freightKg, at: "YUB") == 3_000)

        // The real-week goal reads the same count: two game weeks of it.
        w.setRealDay(RealCalendarTests.day)
        let real = try #require(w.ops.realWeekGoal)
        #expect(real.kind == .freightKg && real.place == "YUB" && real.target == 6_000)
    }
}
