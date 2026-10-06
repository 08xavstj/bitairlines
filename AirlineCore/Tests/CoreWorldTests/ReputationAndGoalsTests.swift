import Foundation
import Testing
import CoreCatalog
@testable import CoreWorld

@Suite struct ReputationAndGoalsTests {
    /// A Caravan on Inuvik - Tuktoyaktuk with no weather or daylight holds, so a sensible schedule runs on time.
    static func easyFlyingWorld(frequency: Double) throws -> World {
        var w = try Fixtures.world(mode: .easy)
        let route = try w.createRoute(stops: ["YEV", "YUB"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        try w.setFrequency(routeID: route, perDay: frequency)
        return w
    }

    // MARK: Reputation

    @Test func flightsRunningLateForWeeksLowerReputation() throws {
        // Twenty-four departures a day each way is far more than one Caravan can keep: nearly every departure leaves late.
        var w = try Fixtures.flyingWorld(frequency: 24)
        w.pausePolicy = .never
        w.airline.reputation = 40
        w.advance(byMinutes: 35 * 1440)
        let share = w.ops.onTime.share
        #expect(share < 0.6)
        #expect(w.airline.reputation < 40)
        let lastFound = w.ops.reputationBook?.lastWeek
        let last = try #require(lastFound)
        let end = try #require(last.endReputation)
        #expect(end < last.startReputation)
        #expect(last.drift < 0, "a late airline drifts down towards a low target")
        #expect((last.target ?? 100) < 40)
        let trend = w.reputationTrend
        #expect(trend.reasons.contains(.belowStandard) || trend.reasons.contains(.lateFlights) || trend.reasons.contains(.missedFlights))
    }

    @Test func goodServiceRaisesReputationAndIsNotDraggedDown() throws {
        var w = try Self.easyFlyingWorld(frequency: 1)
        w.pausePolicy = .never
        w.airline.reputation = 30
        w.advance(byMinutes: 29 * 1440)
        let lastFound = w.ops.reputationBook?.lastWeek
        let last = try #require(lastFound)
        // A rare breakdown grounds the only aircraft (nobody resolves it here) and costs more than a month of flying earns.
        let brokeDown = w.news.contains { $0.kind == .breakdown }
        if !brokeDown {
            let share = w.ops.onTime.share
            #expect(share > 0.9)
            #expect(last.drift == 0, "a punctual airline sits below its target, so nothing drifts")
            #expect((last.target ?? 0) > 30)
            #expect(last.flightGain > last.lateLoss)
            #expect(w.airline.reputation > 30)
        }
    }

    @Test func aRouteWithEveryAircraftInTheHangarMissesItsDepartures() throws {
        var w = try Fixtures.flyingWorld(frequency: 2)
        w.aircraft[0].status = .maintenance(until: w.clock.minute + 3 * 1440)
        let before = w.airline.reputation
        let expected = Int((w.routes[0].frequency * Double(w.routes[0].legs.count)).rounded(.up))
        w.checkMissedDepartures()
        let missed = w.ops.reputationBook?.thisWeek.missed
        #expect(missed == expected)
        let after = w.airline.reputation
        #expect(abs((before - after) - Double(expected) * Tuning.reputationPerMissedDeparture) < 1e-9)
    }

    @Test func aNewAirlineIsBelowTheFloorSoItNeverDrifts() throws {
        var w = try Fixtures.world()
        w.pausePolicy = .never
        let start = w.airline.reputation
        #expect(start < Tuning.reputationFloorTarget)
        w.advance(byMinutes: 15 * 1440)
        let trend = w.reputationTrend
        #expect(w.airline.reputation == start)
        #expect(trend.reasons.contains(.quietWeek))
        #expect(trend.direction == .steady)
    }

    // MARK: Place goals

    @Test func aPlaceGoalCountsOnlyArrivalsThereAndPaysOnce() throws {
        var w = try Fixtures.flyingWorld()
        w.startWeeklyGoal(week: 4)
        let goalFound = w.ops.weeklyGoal
        let goal = try #require(goalFound)
        #expect(goal.place == "YUB" && goal.kind == .passengers)
        #expect(goal.reward == Tuning.weeklyGoalBonus(level: 1))
        #expect(goal.target >= (Tuning.placeGoalFloor[.passengers] ?? 1) && goal.target % 5 == 0)

        let home = Flight(from: "YUB", to: "YEV", departedMinute: 0, distanceKm: 140, passengers: 500, cargoKg: 900, revenue: 0, cost: 0, isFerry: false)
        let ferry = Flight(from: "YEV", to: "YUB", departedMinute: 0, distanceKm: 140, passengers: 0, cargoKg: 0, revenue: 0, cost: 0, isFerry: true)
        w.countGoalArrival(home)
        w.countGoalArrival(ferry)
        #expect(w.weeklyGoalProgress == 0, "landings elsewhere and empty ferries do not count")

        let there = Flight(from: "YEV", to: "YUB", departedMinute: 0, distanceKm: 140, passengers: goal.target, cargoKg: 0, revenue: 0, cost: 0, isFerry: false)
        w.countGoalArrival(there)
        #expect(w.weeklyGoalProgress == goal.target)

        let cash = w.airline.cash
        w.checkWeeklyGoal()
        w.checkWeeklyGoal()
        #expect(w.airline.cash == cash + goal.reward)
        #expect(w.ops.goalsCompleted == 1, "a place goal pays only once")
        #expect(w.news.contains { $0.subject == "goal:passengers:YUB" })
    }

    @Test func aFreightPlaceGoalNamesAPlaceOnACargoRoute() throws {
        var w = try Fixtures.flyingWorld()
        w.startWeeklyGoal(week: 5)
        let goalFound = w.ops.weeklyGoal
        let goal = try #require(goalFound)
        #expect(goal.kind == .freightKg && goal.place == "YUB")
        #expect(goal.target % 100 == 0)
    }

    @Test func placeStepsFallBackToPlainGoalsWithoutANetwork() throws {
        var w = try Fixtures.world()
        w.startWeeklyGoal(week: 4)
        let goalFound = w.ops.weeklyGoal
        let goal = try #require(goalFound)
        #expect(goal.place == nil && goal.kind == .passengers)
    }

    @Test func landingsCountTowardsThePlaceGoalAsTheyHappen() throws {
        var w = try Fixtures.flyingWorld()
        w.pausePolicy = .never
        w.startWeeklyGoal(week: 4)
        let toYUB = w.routes[0].legs.indices.filter { w.routes[0].legs[$0].to == "YUB" }
        let carriedBefore = toYUB.reduce(0) { $0 + w.routes[0].legs[$1].passengersCarried }
        let paxBefore = w.airline.stats.passengers
        // Fly until late this evening, before the midnight update can start a new week's goal.
        let lateEvening = (w.clock.dayIndex + 1) * 1440 - 60
        let span = lateEvening - w.clock.minute
        w.advance(byMinutes: span)
        let goalFound = w.ops.weeklyGoal
        let goal = try #require(goalFound)
        #expect(goal.week == 4 && goal.place == "YUB")
        let carried = toYUB.reduce(0) { $0 + w.routes[0].legs[$1].passengersCarried } - carriedBefore
        #expect(w.weeklyGoalProgress == carried)
        #expect(w.airline.stats.passengers - paxBefore >= carried)
    }

    @Test func anOldWeeklyGoalStillDecodes() throws {
        let json = #"{"week":12,"kind":"freightKg","target":900,"baseline":100,"startTotals":{"passengers":5,"freightKg":100},"reward":5000,"done":false}"#
        let goal = try JSONDecoder().decode(WeeklyGoal.self, from: Data(json.utf8))
        #expect(goal.kind == .freightKg && goal.target == 900 && goal.reward == 5000)
        #expect(goal.place == nil && goal.placeCount == 0)

        var w = try Fixtures.world()
        w.ops.weeklyGoal = goal
        w.airline.stats.cargoKg = 400
        #expect(w.weeklyGoalProgress == 300)
    }

    @Test func operationsWithoutAReputationBookStillDecode() throws {
        let loaded = try JSONDecoder().decode(Operations.self, from: Data("{}".utf8))
        #expect(loaded.reputationBook == nil)
        var w = try Fixtures.flyingWorld()
        w.pausePolicy = .never
        w.advance(byMinutes: 9 * 1440)
        let data = try Fixtures.encode(w)
        let back = try JSONDecoder().decode(World.self, from: data)
        #expect(back.ops.reputationBook == w.ops.reputationBook)
        #expect(back.ops.reputationBook != nil)
    }
}
