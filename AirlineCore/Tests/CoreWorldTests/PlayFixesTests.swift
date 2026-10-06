import Testing
import CoreCatalog
@testable import CoreWorld

@Suite struct PlayFixesTests {
    @Test func aWeatherNoticeLeavesTheInboxWhenTheAirportOpens() throws {
        var w = try Fixtures.world()
        w.pausePolicy = .never
        let until = (w.clock.dayIndex + 2) * 1440
        w.raise(.weather(airport: "YUB", untilMinute: until), options: [IssueOption(choice: .acknowledge, costUSD: 0, days: 0)])
        #expect(w.issues.contains { if case .weather = $0.kind { return true } else { return false } })
        w.advance(byMinutes: 3 * 1440)
        #expect(!w.issues.contains { if case .weather(_, let u) = $0.kind { return u == until } else { return false } })
    }

    @Test func anAircraftThatCannotLandAtHomeCannotBeBought() throws {
        var w = try Fixtures.world()
        w.airline.cash = 50_000_000
        let float = try Fixtures.type("c208f")
        #expect(w.homeProblem(float) == .aircraftCannotUse(airport: "YEV"))
        #expect(w.homeProblem(try Fixtures.type("c208")) == nil)
        w.market.listings.append(UsedListing(id: 9_999, typeID: "c208f", ageYears: 10, condition: 80, price: 1_000_000, deliveryDays: 3))
        #expect(throws: WorldError.aircraftCannotUse(airport: "YEV")) { try w.buyUsed(listingID: 9_999) }
    }

    @Test func aNewGameHasAWeeklyGoalAndMeetingItPaysOnce() throws {
        var w = try Fixtures.world()
        let goalFound = w.ops.weeklyGoal
        let goal = try #require(goalFound)
        #expect(goal.target >= (Tuning.weeklyGoalFloor[goal.kind] ?? 1))
        #expect(goal.reward >= Tuning.weeklyGoalMinimumReward && !goal.done)
        #expect(w.weeklyGoalProgress == 0)

        // Pretend the airline did the whole week's work today.
        switch goal.kind {
        case .passengers: w.airline.stats.passengers += goal.target
        case .freightKg: w.airline.stats.cargoKg += goal.target
        case .flights: w.airline.stats.flights += goal.target
        case .revenue: w.airline.stats.revenue += goal.target
        }
        let cash = w.airline.cash
        w.checkWeeklyGoal()
        #expect(w.ops.weeklyGoal?.done == true && w.ops.goalsCompleted == 1)
        #expect(w.airline.cash == cash + goal.reward)
        w.checkWeeklyGoal()
        #expect(w.ops.goalsCompleted == 1, "a goal pays only once")
    }

    @Test func eachMondayBringsTheNextKindOfGoal() throws {
        var w = try Fixtures.world()
        w.pausePolicy = .never
        let firstFound = w.ops.weeklyGoal
        let first = try #require(firstFound)
        w.advance(byMinutes: 8 * 1440)
        let nextFound = w.ops.weeklyGoal
        let next = try #require(nextFound)
        #expect(next.week > first.week)
        #expect(next.kind != first.kind || WeeklyGoalKind.allCases.count == 1)
    }
}
