// CoreWorld/RealWeekGoal.swift: a second weekly goal that runs Monday to Sunday on the player's real calendar (RealDay.swift),
// next to the game-week goal (WeeklyGoals.swift). It is always tied to a place on the network, using the same place list as
// the game-week place goals; passengers in even real weeks, freight in odd ones. Meeting it pays a fixed bonus by level.
// The kind and place follow the real week number (no random draw).
import CoreCatalog

// MARK: Real-week goal
extension Tuning {
    /// The bonus for a real-week goal, by certificate level 1...7.
    public static let realWeekGoalBonusByLevel = [12_000, 25_000, 50_000, 100_000, 200_000, 400_000, 800_000]
    /// A real week usually holds a few game weeks of play: the target is this many game weeks of what lands there now.
    static let realWeekGoalGameWeeks = 2.0
    /// Floors (passengers, kg).
    static let realWeekGoalFloor: [WeeklyGoalKind: Int] = [.passengers: 20, .freightKg: 600]
    /// Average load assumed when working out what lands at a place (share of the biggest aircraft's seats or hold).
    static let realWeekGoalLoad = 0.5

    public static func realWeekGoalBonus(level: Int) -> Int {
        let table = realWeekGoalBonusByLevel
        return table[min(max(level, 1), table.count) - 1]
    }
}

extension World {
    /// How far the real-week goal has come (0 when there is none).
    public var realWeekGoalProgress: Int { ops.realWeekGoal?.placeCount ?? 0 }

    /// Days left in this real week, today included (7 on Monday, 1 on Sunday). 0 before the app has passed a real day.
    public var realWeekDaysLeft: Int { ops.realDay > 0 ? 7 - RealCalendar.weekday(realDay: ops.realDay) : 0 }

    /// Sets this real week's goal when the week has turned (or there is none yet and a place to name).
    mutating func startRealWeekGoalIfNeeded() {
        let week = RealCalendar.week(realDay: ops.realDay)
        if let goal = ops.realWeekGoal, goal.week == week { return }
        ops.realWeekGoal = makeRealWeekGoal(week: week)
    }

    /// The goal for a real week: a place and a target. Nil while the network has no place other than home.
    func makeRealWeekGoal(week: Int) -> WeeklyGoal? {
        var kind: WeeklyGoalKind = week % 2 == 0 ? .passengers : .freightKg
        var places = goalPlaces(freight: kind == .freightKg)
        if places.isEmpty && kind == .freightKg {
            kind = .passengers
            places = goalPlaces(freight: false)
        }
        guard !places.isEmpty else { return nil }
        // Offset from the game-week rotation so the two goals rarely name the same place.
        let place = places[(week / 2 + 2) % places.count]
        let perFlight = kind == .passengers ? Double(biggestSeats()) : Double(biggestHold())
        var landingsLastWeek = 0
        for route in routes {
            for leg in route.legs where leg.to == place { landingsLastWeek += leg.departuresLastWeek }
        }
        let expected = Double(landingsLastWeek) * perFlight * Tuning.realWeekGoalLoad * Tuning.realWeekGoalGameWeeks
        let step = max(1, Tuning.placeGoalStep[kind] ?? 1)
        let raw = max(Tuning.realWeekGoalFloor[kind] ?? 1, Int(expected.rounded()))
        let target = (raw + step - 1) / step * step
        return WeeklyGoal(week: week, kind: kind, target: target, baseline: 0, startTotals: [:],
                          reward: Tuning.realWeekGoalBonus(level: airline.level), done: false, place: place, placeCountStore: 0)
    }

    /// Counts a landing towards the real-week goal and pays the bonus when it is met (news subject
    /// "realgoal:<kind>:<airport>", amount the bonus). Called from `arrive` for every landing.
    mutating func countRealWeekArrival(_ flight: Flight) {
        guard !flight.isFerry, var goal = ops.realWeekGoal, !goal.done, goal.place == flight.to else { return }
        switch goal.kind {
        case .passengers: goal.placeCount += flight.passengers
        case .freightKg: goal.placeCount += flight.cargoKg
        case .flights, .revenue: return
        }
        if goal.placeCount >= goal.target {
            goal.done = true
            ops.realWeekGoalsMet += 1
            airline.cash += goal.reward
            addNews(.milestone, subject: "realgoal:\(goal.kind.rawValue):\(goal.place ?? "")", amount: goal.reward)
        }
        ops.realWeekGoal = goal
    }
}
