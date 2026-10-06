import Foundation
import Testing
import CoreCatalog
@testable import CoreWorld

/// The real calendar: the daily dispatch and its stamps, the real-week goal, seasonal events and the logbook.
@Suite struct RealCalendarTests {
    /// Tuesday 6 October 2026, as the app would pass it in.
    static let day = 9775

    @Test func realDaysCountFromTheFirstOf2000() {
        #expect(RealCalendar.realDay(year: 2000, month: 1, day: 1) == 0)
        #expect(RealCalendar.realDay(year: 2026, month: 10, day: 6) == Self.day)
        #expect(RealCalendar.date(realDay: Self.day) == CalendarDate(year: 2026, month: 10, day: 6))
        #expect(RealCalendar.date(realDay: RealCalendar.realDay(year: 2028, month: 2, day: 29)) == CalendarDate(year: 2028, month: 2, day: 29))
        #expect(RealCalendar.weekday(realDay: Self.day) == 1, "a Tuesday")
        let monday = RealCalendar.monday(ofWeek: RealCalendar.week(realDay: Self.day))
        #expect(monday == Self.day - 1)
        #expect(RealCalendar.week(realDay: monday + 6) == RealCalendar.week(realDay: Self.day), "Sunday closes the week")
        #expect(RealCalendar.week(realDay: monday + 7) == RealCalendar.week(realDay: Self.day) + 1)
    }

    // MARK: Daily dispatch

    @Test func theDispatchIsTheSameForTheSameDayAndNetworkAndChangesTheNextDay() throws {
        var a = try Fixtures.flyingWorld(seed: 7)
        var b = try Fixtures.flyingWorld(seed: 99)
        a.refreshJobArea()
        b.refreshJobArea()
        let planA = try #require(a.dispatchPlan(realDay: Self.day))
        let planB = try #require(b.dispatchPlan(realDay: Self.day))
        #expect(planA == planB, "same day, same network: same dispatch")
        let tomorrow = try #require(a.dispatchPlan(realDay: Self.day + 1))
        #expect(tomorrow != planA)
        let week = (0..<7).compactMap { a.dispatchPlan(realDay: Self.day + $0) }
        #expect(Set(week).count >= 3, "it varies through the week")
        #expect(planA.from != planA.to && planA.pay > 0)
        #expect(planA.from == "YEV" || planA.from == "YUB" || planA.to == "YEV" || planA.to == "YUB", "one end is on the network")
    }

    @Test func settingTheRealDayPostsOneDispatchAndANewDayReplacesIt() throws {
        var w = try Fixtures.flyingWorld()
        let rngBefore = w.rng
        w.setRealDay(Self.day)
        let first = try #require(w.dispatchToday)
        #expect(first.dispatchDay == Self.day)
        w.setRealDay(Self.day)
        #expect(w.ops.jobs.filter { $0.dispatchDay != nil }.count == 1, "the same day posts nothing new")
        w.setRealDay(Self.day + 1)
        let second = try #require(w.dispatchToday)
        #expect(second.dispatchDay == Self.day + 1)
        #expect(!w.ops.jobs.contains { $0.id == first.id }, "yesterday's untaken dispatch went")
        #expect(w.rng == rngBefore, "the world's own random stream is untouched")
        w.advance(byMinutes: 5 * 1440)
        #expect(w.ops.jobs.contains { $0.id == second.id }, "it stays on the board while the real day lasts")
    }

    @Test func aStampIsEarnedOncePerRealDay() throws {
        var w = try Fixtures.flyingWorld()
        w.setRealDay(Self.day)
        let job = try #require(w.dispatchToday)
        w.noteSpecialJobDone(job)
        w.noteSpecialJobDone(job)
        #expect(w.ops.dispatch.stamps == 1)
        #expect(w.dispatchStampedToday)
        #expect(w.stampsToNextReward == Tuning.stampsPerReward - 1)
        w.earnStamp(day: Self.day + 1)
        #expect(w.ops.dispatch.stamps == 2)
    }

    @Test func sevenStampsUnlockALiveryAndARareFind() throws {
        var w = try Fixtures.flyingWorld()
        let rareBefore = w.rareListings.count
        // Not in a row: every other day.
        for n in 0..<6 { w.earnStamp(day: Self.day + 2 * n) }
        #expect(w.ops.unlockedLiveries.isEmpty, "no reward before the seventh stamp")
        w.earnStamp(day: Self.day + 20)
        #expect(w.ops.dispatch.stamps == 7)
        #expect(w.ops.dispatch.rewardsEarned == 1)
        #expect(w.ops.unlockedLiveries == [UnlockableLiveries.classicCodes[0]])
        #expect(w.rareListings.count == rareBefore + 1, "a rare find in the hangar")
        #expect(w.news.contains { $0.subject.hasPrefix("stampreward:") })
        #expect(w.stampsToNextReward == Tuning.stampsPerReward)

        let plane = w.aircraft[0].id
        try w.paintEarnedLivery(code: UnlockableLiveries.classicCodes[0], aircraftID: plane)
        #expect(w.aircraft[0].livery?.name == UnlockableLiveries.classicCodes[0])
        var refused = false
        do { try w.paintEarnedLivery(code: UnlockableLiveries.classicCodes[1], aircraftID: plane) } catch { refused = true }
        #expect(refused, "a scheme not yet earned cannot be painted")
    }

    @Test func everyEarnedLiveryHasAPaintScheme() {
        for code in UnlockableLiveries.allCodes {
            #expect(UnlockableLiveries.livery(code: code, logo: Branding.starter.logo) != nil, "\(code) has no paint")
        }
        #expect(Set(UnlockableLiveries.allCodes).count == UnlockableLiveries.allCodes.count)
    }

    // MARK: Seasonal events

    @Test func eventsSwitchOnAndOffByDate() throws {
        func day(_ y: Int, _ m: Int, _ d: Int) -> Int { RealCalendar.realDay(year: y, month: m, day: d) }
        #expect(SeasonalEvents.active(onRealDay: day(2026, 10, 6))?.kind == .harvestFreight)
        #expect(SeasonalEvents.active(onRealDay: day(2026, 12, 10))?.kind == .holidayParcels)
        #expect(SeasonalEvents.active(onRealDay: day(2026, 12, 24)) == nil)
        #expect(SeasonalEvents.active(onRealDay: day(2026, 2, 17))?.kind == .newYearRush)
        #expect(SeasonalEvents.active(onRealDay: day(2027, 7, 20))?.kind == .summerPeak)
        #expect(SeasonalEvents.active(onRealDay: day(2027, 5, 20)) == nil)
        let next = SeasonalEvents.next(afterRealDay: day(2026, 12, 24))
        #expect(next.kind == .newYearRush && next.startDay == day(2027, 1, 30))

        // Every event lasts one to three weeks, and none overlap.
        for year in 2026...2040 {
            let windows = SeasonKind.allCases.map { SeasonalEvents.window($0, year: year) }.sorted { $0.startDay < $1.startDay }
            for w in windows { #expect(w.endDay - w.startDay + 1 >= 7 && w.endDay - w.startDay + 1 <= 21, "\(w.kind) \(year)") }
            for (a, b) in zip(windows, windows.dropFirst()) { #expect(a.endDay < b.startDay, "\(a.kind) overlaps \(b.kind) in \(year)") }
        }

        var w = try Fixtures.flyingWorld()
        w.setRealDay(day(2026, 10, 6))
        #expect(w.activeSeason?.kind == .harvestFreight)
        #expect(w.ops.jobs.contains { $0.season == .harvestFreight }, "event jobs on the board")
        let yev = try Fixtures.airport("YEV")
        let yub = try Fixtures.airport("YUB")
        #expect(w.seasonFactors(from: yev, to: yub).cargo == Tuning.seasonLift(.harvestFreight).cargo)
        w.setRealDay(day(2026, 10, 20))
        #expect(w.activeSeason == nil)
        #expect(!w.ops.jobs.contains { $0.season != nil && !$0.isTaken }, "untaken event jobs go when it ends")
        #expect(w.seasonFactors(from: yev, to: yub).cargo == 1)
    }

    @Test func threeEventJobsUnlockTheEventLivery() throws {
        var w = try Fixtures.flyingWorld()
        w.setRealDay(RealCalendar.realDay(year: 2026, month: 12, day: 10))
        w.countSeasonJob(.holidayParcels)
        w.countSeasonJob(.holidayParcels)
        #expect(!w.ops.unlockedLiveries.contains(UnlockableLiveries.seasonCode(.holidayParcels)))
        w.countSeasonJob(.harvestFreight)
        #expect(w.ops.season.jobsDone == 2, "a job from another event does not count")
        w.countSeasonJob(.holidayParcels)
        #expect(w.ops.unlockedLiveries.contains(UnlockableLiveries.seasonCode(.holidayParcels)))
    }

    // MARK: Real-week goal

    @Test func theRealWeekGoalNamesAPlaceAndPaysOnce() throws {
        var w = try Fixtures.flyingWorld()
        w.advance(byMinutes: 8 * 1440)
        w.setRealDay(Self.day)
        let goal = try #require(w.ops.realWeekGoal)
        #expect(goal.week == RealCalendar.week(realDay: Self.day))
        #expect(goal.place == "YUB", "the only place on the network besides home")
        #expect(goal.reward == Tuning.realWeekGoalBonus(level: w.airline.level))
        #expect(w.realWeekDaysLeft == 6)

        let cash = w.airline.cash
        let flight = Flight(from: "YEV", to: "YUB", departedMinute: w.clock.minute, distanceKm: 127, passengers: goal.target, cargoKg: goal.target,
                            revenue: 0, cost: 0, isFerry: false)
        w.countRealWeekArrival(flight)
        w.countRealWeekArrival(flight)
        #expect(w.ops.realWeekGoal?.done == true)
        #expect(w.ops.realWeekGoalsMet == 1)
        #expect(w.airline.cash == cash + goal.reward, "paid once")

        w.setRealDay(Self.day + 7)
        #expect(w.ops.realWeekGoal?.week == goal.week + 1)
        #expect(w.ops.realWeekGoal?.done == false)
    }

    // MARK: Logbook

    @Test func theLogbookRecordsANewAirportOnce() throws {
        var w = try Fixtures.world()
        let i = 0
        w.logLanding(aircraftIndex: i, at: "YUB")
        w.logLanding(aircraftIndex: i, at: "YUB")
        w.logLanding(aircraftIndex: i, at: "YEV")
        #expect(w.logbook.airports.count == 2)
        #expect(w.logbook.airports["YUB"]?.landings == 2)
        #expect(w.logbook.types.count == 1 && w.logbook.types["c208"] != nil)
        #expect(w.logbook.countriesVisited.first?.country == "CA" && w.logbook.countriesVisited.first?.airports == 2)

        var flying = try Fixtures.flyingWorld()
        flying.advance(byMinutes: 3 * 1440)
        #expect(flying.logbook.airports["YUB"] != nil, "landings on a route are logged")
    }

    // MARK: Saves

    @Test func anOlderSaveWithoutTheRealCalendarLoads() throws {
        var w = try Fixtures.flyingWorld()
        w.setRealDay(Self.day)
        w.earnStamp(day: Self.day)
        let data = try Fixtures.encode(w)
        let loaded = try JSONDecoder().decode(World.self, from: data)
        #expect(loaded.ops.dispatch.stamps == 1 && loaded.ops.realDay == Self.day)
        #expect(loaded.dispatchToday?.dispatchDay == Self.day, "a dispatch job keeps its day")

        // Strip everything this feature added, as a save from before it would look.
        var root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var ops = try #require(root["operationsStore"] as? [String: Any])
        for key in ["realDay", "dispatch", "realWeekGoal", "realWeekGoalsMet", "season", "unlockedLiveries", "logbook"] { ops[key] = nil }
        if let jobs = ops["jobs"] as? [[String: Any]] {
            ops["jobs"] = jobs.map { job -> [String: Any] in
                var j = job
                j["dispatchDay"] = nil
                j["season"] = nil
                return j
            }
        }
        root["operationsStore"] = ops
        let old = try JSONSerialization.data(withJSONObject: root)
        var older = try JSONDecoder().decode(World.self, from: old)
        #expect(older.ops.realDay == 0 && older.ops.dispatch.stamps == 0 && older.logbook.airports.isEmpty)
        older.advance(byMinutes: 3 * 1440)
        #expect(older.airline.stats.flights > 0, "and keeps flying")
    }
}
