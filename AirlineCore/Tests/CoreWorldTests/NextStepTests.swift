import Testing
import CoreCatalog
@testable import CoreWorld

/// The one line on the map that says what to do next.
@Suite struct NextStepTests {
    /// A new airline with its Caravan on Inuvik - Tuktoyaktuk.
    func flying() throws -> World {
        var w = try Fixtures.world()
        let routeID = try w.createRoute(stops: ["YEV", "YUB"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: routeID)
        return w
    }

    @Test func aNewAirlineIsToldToOpenARouteThenToAssignItsAircraft() throws {
        var w = try Fixtures.world()
        #expect(w.nextStep == .openFirstRoute)
        _ = try w.createRoute(stops: ["YEV", "YUB"])
        #expect(w.nextStep == .assignAircraft(aircraftID: w.aircraft[0].id))
    }

    @Test func withoutTheCashItSaysWhatToSaveFor() throws {
        var w = try flying()
        w.airline.cash = 0
        let step = w.nextStep
        if case .saveForAircraft(let typeID, let price, let days) = step {
            #expect(AircraftCatalog.type(typeID) != nil)
            #expect(price > 0)
            #expect(days == nil, "no finished day yet, so no estimate")
        } else {
            Testing.Issue.record("expected an aircraft to save for, got \(step)")
        }
    }

    @Test func withNothingToBuyItPointsAtTheNextLevel() throws {
        var w = try flying()
        w.market.listings = []
        #expect(w.nextStep == .levelNeedsReputation(level: 2, reputation: 11))

        w.airline.reputation = 20
        let missing = 1_500_000 - w.airline.stats.revenue
        #expect(w.nextStep == .levelNeedsRevenue(level: 2, revenue: missing, days: nil))

        w.airline.stats.revenue = 2_000_000
        w.airline.cash = 1_000_000
        #expect(w.nextStep == .buyLevel(level: 2, fee: 150_000))

        w.airline.cash = 100_000
        #expect(w.nextStep == .saveForLevel(level: 2, fee: 150_000, days: nil))

        w.airline.level = Airline.maxLevel
        #expect(w.nextStep == .topLevel)
    }

    @Test func savingTimeComesFromTheRecentDays() throws {
        var w = try flying()
        let before = w.averageDaily { $0.net }
        #expect(before == nil)
        w.books = [DayBook(day: 0, revenue: 1_000, flightCosts: 300, overhead: 100), DayBook(day: 1, revenue: 1_400, flightCosts: 300, overhead: 100)]
        let average = w.averageDaily { $0.net }
        #expect(average == 800)
        #expect(w.daysToSave(8_000) == 10)
        #expect(w.daysToSave(8_001) == 11)
        #expect(w.daysToSave(0) == 0)
        #expect(w.daysToReach(100, perDay: 0) == nil)
        #expect(w.daysToReach(100, perDay: -5) == nil)
        #expect(w.daysToReach(Tuning.nextStepMaxDays * 10, perDay: 1) == nil, "too far off to name a day")
    }
}
