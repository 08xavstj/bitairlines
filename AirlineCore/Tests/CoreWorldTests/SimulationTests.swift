import Testing
import Foundation
import CoreCatalog
@testable import CoreWorld

@Suite struct SimulationTests {
    @Test func theClockAndCalendarAgree() {
        #expect(CalendarDate(dayIndex: 0) == CalendarDate(year: 2027, month: 1, day: 1))
        #expect(CalendarDate(dayIndex: 31) == CalendarDate(year: 2027, month: 2, day: 1))
        #expect(CalendarDate(dayIndex: 365) == CalendarDate(year: 2028, month: 1, day: 1))
        #expect(CalendarDate(dayIndex: 365 + 59) == CalendarDate(year: 2028, month: 2, day: 29))
        #expect(GameClock(minute: 0).weekday == 4)
        #expect(GameClock(minute: 3 * 1440).weekday == 0)
        #expect(GameClock(minute: 6 * 60 + 30).hour == 6)
    }

    @Test func anAircraftFliesTheRouteAndEarns() throws {
        var w = try Fixtures.flyingWorld()
        Fixtures.light(&w, "YUB")
        #expect(w.advance(byMinutes: 30 * 1440) == .reachedTarget)
        #expect(w.clock.minute == 6 * 60 + 30 * 1440)
        #expect(w.airline.stats.flights > 60, "flights: \(w.airline.stats.flights)")
        #expect(w.airline.stats.passengers > 100)
        #expect(w.airline.stats.revenue > 0 && w.airline.stats.expenses > 0)
        #expect(w.routes[0].flights > 60 && w.routes[0].legs.allSatisfy { $0.maturity > 0.3 })
        #expect(!w.books.isEmpty)
    }

    @Test func januaryDarknessAtAnUnlitStripLimitsTheSchedule() throws {
        var dark = try Fixtures.flyingWorld(frequency: 2)
        var lit = try Fixtures.flyingWorld(frequency: 2)
        Fixtures.light(&lit, "YUB")
        dark.advance(byMinutes: 20 * 1440)
        lit.advance(byMinutes: 20 * 1440)
        #expect(lit.airline.stats.flights > dark.airline.stats.flights, "\(lit.airline.stats.flights) lit vs \(dark.airline.stats.flights) dark")
        #expect(dark.airline.stats.flights >= 30, "still about a round trip a day in the polar twilight")
    }

    @Test func nobodyFliesWithoutARoute() throws {
        var w = try Fixtures.world()
        let cash = w.airline.cash
        w.advance(byMinutes: 10 * 1440)
        #expect(w.airline.stats.flights == 0)
        #expect(w.airline.cash < cash, "overhead still runs")
    }

    @Test func lowerFrequencyFliesFewerLegs() throws {
        var busy = try Fixtures.flyingWorld(frequency: 2)
        var quiet = try Fixtures.flyingWorld(frequency: 0.5)
        Fixtures.light(&busy, "YUB")
        Fixtures.light(&quiet, "YUB")
        busy.advance(byMinutes: 20 * 1440)
        quiet.advance(byMinutes: 20 * 1440)
        #expect(busy.airline.stats.flights > quiet.airline.stats.flights * 2, "\(busy.airline.stats.flights) vs \(quiet.airline.stats.flights)")
    }

    @Test func theSameSeedGivesTheSameHistory() throws {
        var a = try Fixtures.flyingWorld(seed: 11), b = try Fixtures.flyingWorld(seed: 11)
        a.advance(byMinutes: 60 * 1440)
        b.advance(byMinutes: 60 * 1440)
        #expect(try Fixtures.encode(a) == Fixtures.encode(b))
        var c = try Fixtures.flyingWorld(seed: 12)
        c.advance(byMinutes: 60 * 1440)
        #expect(c.airline.cash != a.airline.cash, "a different seed should change fuel prices and weather")
    }

    @Test func advancingInSmallStepsMatchesOneBigJump() throws {
        var jump = try Fixtures.flyingWorld(seed: 3), steps = try Fixtures.flyingWorld(seed: 3)
        jump.advance(byMinutes: 14 * 1440)
        for _ in 0..<(14 * 24) { steps.advance(byMinutes: 60) }
        #expect(try Fixtures.encode(jump) == Fixtures.encode(steps))
    }

    @Test func aSavedGameResumesIdentically() throws {
        var w = try Fixtures.flyingWorld(seed: 5)
        w.advance(byMinutes: 20 * 1440)
        var copy = try JSONDecoder().decode(World.self, from: Fixtures.encode(w))
        w.advance(byMinutes: 40 * 1440)
        copy.advance(byMinutes: 40 * 1440)
        #expect(try Fixtures.encode(w) == Fixtures.encode(copy))
    }

    @Test func aBreakdownStopsTheGameUntilResolved() throws {
        var w = try Fixtures.flyingWorld()
        Fixtures.advanceUntilBoarding(&w)
        w.raiseBreakdown(aircraftIndex: 0, type: try #require(AircraftCatalog.type("c208")))
        let issue = try #require(w.issues.first)
        #expect(issue.pausesGame && issue.isCritical && issue.options.count == 3)
        #expect(w.advance(byMinutes: 1440) == .pausedForIssue)
        let frozen = w.clock.minute
        #expect(w.advance(byMinutes: 100) == .pausedForIssue && w.clock.minute == frozen)

        let cash = w.airline.cash
        try w.resolve(issueID: issue.id, choice: .flyInMechanic)
        #expect(w.issues.isEmpty && w.airline.cash == cash - issue.options[1].costUSD)
        #expect(w.advance(byMinutes: 10 * 1440) == .reachedTarget)
        #expect(w.airline.stats.flights > 0)
    }

    @Test func theNeverPolicyKeepsRunningWithAGroundedAircraft() throws {
        var w = try Fixtures.flyingWorld()
        w.setPausePolicy(.never)
        Fixtures.advanceUntilBoarding(&w)
        w.raiseBreakdown(aircraftIndex: 0, type: try #require(AircraftCatalog.type("c208")))
        #expect(w.advance(byMinutes: 5 * 1440) == .reachedTarget)
        #expect(w.issues.count == 1)
        if case .grounded = w.aircraft[0].status {} else { Issue.record("the aircraft should still be grounded") }
        w.setPausePolicy(.critical)
        #expect(w.advance(byMinutes: 1440) == .pausedForIssue)
    }

    @Test func unaffordableRepairsAreRefused() throws {
        var w = try Fixtures.flyingWorld()
        Fixtures.advanceUntilBoarding(&w)
        w.raiseBreakdown(aircraftIndex: 0, type: try #require(AircraftCatalog.type("c208")))
        w.airline.cash = 10
        let issue = try #require(w.issues.first)
        #expect(throws: WorldError.notEnoughCash(needed: issue.options[0].costUSD)) { try w.resolve(issueID: issue.id, choice: .repairNow) }
        try w.resolve(issueID: issue.id, choice: .waitForParts)
        #expect(throws: WorldError.unknownIssue(issue.id)) { try w.resolve(issueID: issue.id, choice: .waitForParts) }
    }

    @Test func runningOutOfMoneyRaisesAnOverdraftNotice() throws {
        var w = try Fixtures.world()
        w.airline.cash = -500_000
        #expect(w.advance(byMinutes: 2 * 1440) == .pausedForIssue)
        let issue = try #require(w.issues.first { if case .overdraft = $0.kind { return true } else { return false } })
        #expect(issue.options.map(\.choice) == [.emergencyLoan, .declareBankruptcy])
        let before = w.airline.cash
        try w.resolve(issueID: issue.id, choice: .emergencyLoan)
        #expect(w.airline.loans.count == 1 && w.airline.cash == before + Tuning.emergencyLoanAmount)
    }

    @Test func stayingOverdrawnEndsTheGame() throws {
        var w = try Fixtures.world()
        w.airline.cash = -5_000_000
        w.setPausePolicy(.never)
        #expect(w.advance(byMinutes: 30 * 1440) == .gameOver)
        #expect(w.isBankrupt)
        #expect(w.advance(byMinutes: 1440) == .gameOver)
    }

    @Test func qualifyingForALevelRaisesANoticeAndTheUpgradeIsPaidFor() throws {
        var w = try Fixtures.world()
        w.airline.stats.revenue = 2_000_000
        w.airline.reputation = 20
        w.airline.cash = 1_000_000
        #expect(w.advance(byMinutes: 2 * 1440) == .reachedTarget)
        #expect(w.issues.contains { if case .certificateReady(let level) = $0.kind { return level == 2 } else { return false } })
        #expect(w.canUpgradeCertificate)
        let cash = w.airline.cash
        try w.upgradeCertificate()
        #expect(w.airline.level == 2 && w.airline.cash == cash - 150_000)
        #expect(!w.issues.contains { if case .certificateReady = $0.kind { return true } else { return false } })
        #expect(throws: WorldError.requirementsNotMet) { try w.upgradeCertificate() }
    }

    @Test func aClosedAirportHoldsTheFlights() throws {
        var w = try Fixtures.flyingWorld()
        w.market.closures.append(Closure(airport: "YUB", untilMinute: w.clock.minute + 3 * 1440))
        w.advance(byMinutes: 2 * 1440)
        #expect(w.airline.stats.flights == 0)
        w.advance(byMinutes: 5 * 1440)
        #expect(w.airline.stats.flights > 0, "flights resume after the closure")
    }

    @Test func loansArePaidBackMonthByMonth() throws {
        var w = try Fixtures.world()
        try w.takeLoan(amount: 600_000, annualRate: 0.12, months: 12)
        #expect(w.totalDebt == 600_000)
        w.advance(byMinutes: 400 * 1440)
        #expect(w.airline.loans.isEmpty, "twelve monthly payments clear the loan")
        #expect(throws: WorldError.notEnoughCash(needed: 5_000_000 - w.borrowingLimit)) { try w.takeLoan(amount: 5_000_000) }
    }

    @Test func aYearOfFlyingStaysSane() throws {
        var w = try Fixtures.flyingWorld(seed: 21, frequency: 1)
        let start = w.airline.cash
        #expect(w.advance(byMinutes: 365 * 1440) != .gameOver)
        let profit = w.airline.cash - start
        print("CALIBRATION caravan Inuvik-Tuktoyaktuk 1/day, one year: profit \(profit), flights \(w.airline.stats.flights), pax \(w.airline.stats.passengers), cargo \(w.airline.stats.cargoKg) kg, reputation \(w.airline.reputation), condition \(w.aircraft[0].condition)")
        #expect(w.airline.stats.flights > 500)
        #expect(profit > 0, "a sensibly scheduled Caravan should make money on its home route; profit was \(profit)")
        #expect(profit < 3_000_000, "but it should not print money; profit was \(profit)")
        #expect(w.aircraft[0].condition > 40)
    }
}
