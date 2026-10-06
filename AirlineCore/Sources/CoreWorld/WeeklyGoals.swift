// CoreWorld/WeeklyGoals.swift: one goal each game week (carry more people, move more freight, fly more, earn more), set a little
// above what the airline did the week before. Some weeks the goal is tied to a place on the network: carry people to it, or
// deliver freight to it. Meeting a goal pays a fixed bonus by certificate level and counts towards the Game Center leaderboard.
// The kind and the place follow the week number (no random draw), so the other systems' random streams stay the same.
import CoreCatalog

public enum WeeklyGoalKind: String, Sendable, Hashable, Codable, CaseIterable {
    case passengers, freightKg, flights, revenue
}

public struct WeeklyGoal: Sendable, Hashable, Codable {
    /// Game week number (counted from Mondays) the goal belongs to.
    public var week: Int
    public var kind: WeeklyGoalKind
    public var target: Int
    /// The airline's running total when the week began; progress is the total now minus this.
    public var baseline: Int
    /// Every kind's running total when the week began (by kind name), so next week's goal knows what this week achieved.
    public var startTotals: [String: Int]
    public var reward: Int
    public var done: Bool
    /// For a place goal, the airport (IATA code) the passengers or freight must land at. Missing from older saves.
    public var place: String? = nil
    /// For a place goal, what has landed there this week. Missing from older saves; use `placeCount`.
    var placeCountStore: Int? = nil
    /// What landed at each airport this game week (passengers and freight kg, keyed by `arrivalKey`), so the next place goal is
    /// sized by what really lands there. Only on the game-week goal; missing from older saves.
    var arrivalsStore: [String: Int]? = nil
    /// The same for the game week before (the real-week goal reads it).
    var lastWeekArrivalsStore: [String: Int]? = nil
    /// Last week's goal, when it was met: its week and bonus, so the bonus can still be paid again (the optional ad) after the
    /// new goal starts on Monday. Missing from older saves.
    public var previousMetWeek: Int? = nil
    public var previousMetReward: Int? = nil

    public var placeCount: Int {
        get { placeCountStore ?? 0 }
        set { placeCountStore = newValue }
    }

    static func arrivalKey(_ kind: WeeklyGoalKind, _ code: String) -> String { code + (kind == .freightKg ? ":kg" : ":pax") }

    /// What landed at an airport this week, or nil when this goal does not count landings (an older save).
    func arrivals(_ kind: WeeklyGoalKind, at code: String) -> Int? { arrivalsStore.map { $0[WeeklyGoal.arrivalKey(kind, code)] ?? 0 } }

    /// The same for the week before.
    func lastWeekArrivals(_ kind: WeeklyGoalKind, at code: String) -> Int? {
        lastWeekArrivalsStore.map { $0[WeeklyGoal.arrivalKey(kind, code)] ?? 0 }
    }

    /// Adds a landing to this week's table (a goal from an older save has none until next Monday's goal starts one).
    mutating func noteArrival(_ kind: WeeklyGoalKind, at code: String, amount: Int) {
        guard var table = arrivalsStore else { return }
        arrivalsStore = nil
        table[WeeklyGoal.arrivalKey(kind, code), default: 0] += amount
        arrivalsStore = table
    }
}

/// One step of the weekly rotation: a kind of goal, tied to a place or not.
struct GoalSlot: Sendable, Hashable {
    var kind: WeeklyGoalKind
    var atPlace: Bool
}

// MARK: Weekly goals
extension Tuning {
    /// The goal is last week's result times this, at least the floor below.
    public static let weeklyGoalStretch = 1.1
    public static let weeklyGoalFloor: [WeeklyGoalKind: Int] = [.passengers: 30, .freightKg: 800, .flights: 10, .revenue: 10_000]
    /// Floors for a goal tied to one place (only passengers and freight have place goals).
    public static let placeGoalFloor: [WeeklyGoalKind: Int] = [.passengers: 10, .freightKg: 300]
    /// A place goal is rounded up to a multiple of this (150 passengers, 2,000 kg).
    public static let placeGoalStep: [WeeklyGoalKind: Int] = [.passengers: 5, .freightKg: 100]
    /// The bonus for meeting any goal, by certificate level 1...7.
    public static let weeklyGoalBonusByLevel = [8_000, 15_000, 30_000, 60_000, 120_000, 250_000, 500_000]
    /// No bonus is ever below this.
    public static let weeklyGoalMinimumReward = 5_000

    public static func weeklyGoalBonus(level: Int) -> Int {
        let table = weeklyGoalBonusByLevel
        return max(weeklyGoalMinimumReward, table[min(max(level, 1), table.count) - 1])
    }

    /// The rotation, one step a week. Place steps fall back to the plain kind while the network has no place to pick.
    static let weeklyGoalRotation: [GoalSlot] = [
        GoalSlot(kind: .passengers, atPlace: false), GoalSlot(kind: .freightKg, atPlace: false),
        GoalSlot(kind: .flights, atPlace: false), GoalSlot(kind: .revenue, atPlace: false),
        GoalSlot(kind: .passengers, atPlace: true), GoalSlot(kind: .freightKg, atPlace: true),
    ]
}

extension World {
    /// The airline's running total for a kind of goal.
    func goalTotal(_ kind: WeeklyGoalKind) -> Int {
        switch kind {
        case .passengers: airline.stats.passengers
        case .freightKg: airline.stats.cargoKg
        case .flights: airline.stats.flights
        case .revenue: airline.stats.revenue
        }
    }

    /// How far this week's goal has come (0 when there is none).
    public var weeklyGoalProgress: Int {
        guard let goal = ops.weeklyGoal else { return 0 }
        if goal.place != nil { return goal.placeCount }
        return max(0, goalTotal(goal.kind) - goal.baseline)
    }

    /// Airports a place goal may name: every stop the airline flies to except home, sorted. Freight needs a route that carries it.
    func goalPlaces(freight: Bool) -> [String] {
        let home = airline.home
        let stops = routes.filter { !freight || $0.carriesCargo }.flatMap(\.stops)
        return Array(Set(stops)).filter { $0 != home }.sorted()
    }

    /// Share of last week's departures that landed at a place (to scale the airline-wide result down to one airport).
    func shareOfArrivals(at place: String) -> Double {
        var all = 0
        var there = 0
        for route in routes {
            for leg in route.legs {
                all += leg.departuresLastWeek
                if leg.to == place { there += leg.departuresLastWeek }
            }
        }
        return all > 0 ? Double(there) / Double(all) : 0
    }

    /// The goal whose bonus the optional ad pays again: this week's once it is met, else last week's if that was met (a goal
    /// met late on Sunday is paid at midnight, just as the next goal starts). Nil when neither was met. Rewards.swift checks
    /// that its bonus was not paid again already.
    public var goalToDouble: (week: Int, reward: Int)? {
        guard let goal = ops.weeklyGoal else { return nil }
        if goal.done { return (goal.week, goal.reward) }
        guard let week = goal.previousMetWeek, let reward = goal.previousMetReward else { return nil }
        return (week, reward)
    }

    /// Sets the goal for the week that starts now. Called when a game starts and every Monday.
    mutating func startWeeklyGoal() {
        // Weeks are counted from Mondays (weekday 0), the day a new goal starts.
        startWeeklyGoal(week: (clock.dayIndex - clock.weekday + 7) / 7)
    }

    mutating func startWeeklyGoal(week: Int) {
        let rotation = Tuning.weeklyGoalRotation
        let slot = rotation[week % rotation.count]
        let kind = slot.kind
        let previous = ops.weeklyGoal
        // What the airline did last week in this kind of goal.
        let lastWeek = previous.flatMap { $0.startTotals[kind.rawValue] }.map { goalTotal(kind) - $0 } ?? 0
        var target = max(Tuning.weeklyGoalFloor[kind] ?? 1, Int((Double(lastWeek) * Tuning.weeklyGoalStretch).rounded()))

        // A place goal: the airport follows the week number through the sorted list of places.
        var place: String?
        if slot.atPlace {
            let places = goalPlaces(freight: kind == .freightKg)
            if !places.isEmpty {
                let offset = kind == .freightKg ? 1 : 0
                let code = places[(week / rotation.count + offset) % places.count]
                // What landed there last week, counted landing by landing (freight follows the people at the destination, so
                // a village gets far less than its share of departures). A save from before that was counted falls back to
                // last week's result shared out by departures.
                let landed = previous?.arrivals(kind, at: code).map { Double($0) } ?? Double(lastWeek) * shareOfArrivals(at: code)
                let expected = landed * Tuning.weeklyGoalStretch
                let step = max(1, Tuning.placeGoalStep[kind] ?? 1)
                let raw = max(Tuning.placeGoalFloor[kind] ?? 1, Int(expected.rounded()))
                target = (raw + step - 1) / step * step
                place = code
            }
        }

        var totals: [String: Int] = [:]
        for k in WeeklyGoalKind.allCases { totals[k.rawValue] = goalTotal(k) }
        var goal = WeeklyGoal(week: week, kind: kind, target: target, baseline: goalTotal(kind), startTotals: totals,
                              reward: Tuning.weeklyGoalBonus(level: airline.level), done: false,
                              place: place, placeCountStore: place == nil ? nil : 0)
        goal.arrivalsStore = [:]
        goal.lastWeekArrivalsStore = previous?.arrivalsStore
        if let previous, previous.done {
            goal.previousMetWeek = previous.week
            goal.previousMetReward = previous.reward
        }
        ops.weeklyGoal = goal
    }

    /// Counts a landing: what it brought is noted against the airport it landed at (for next week's place goal), and towards
    /// a place goal if it landed at the goal's airport. A goal already met by earlier landings is paid first, so it shows as
    /// done during the week instead of at the next midnight. Called from `arrive` for every landing (route flights and job
    /// deliveries).
    mutating func countGoalArrival(_ flight: Flight) {
        checkWeeklyGoal()
        guard !flight.isFerry, ops.weeklyGoal != nil else { return }
        if flight.passengers > 0 { ops.weeklyGoal?.noteArrival(.passengers, at: flight.to, amount: flight.passengers) }
        if flight.cargoKg > 0 { ops.weeklyGoal?.noteArrival(.freightKg, at: flight.to, amount: flight.cargoKg) }
        guard var goal = ops.weeklyGoal, !goal.done, let place = goal.place, place == flight.to else { return }
        switch goal.kind {
        case .passengers: goal.placeCount += flight.passengers
        case .freightKg: goal.placeCount += flight.cargoKg
        case .flights, .revenue: return
        }
        ops.weeklyGoal = goal
    }

    /// Pays the bonus once the goal is met. Checked every day.
    mutating func checkWeeklyGoal() {
        guard let goal = ops.weeklyGoal, !goal.done, weeklyGoalProgress >= goal.target else { return }
        ops.weeklyGoal?.done = true
        ops.goalsCompleted += 1
        airline.cash += goal.reward
        let subject = goal.place.map { "goal:\(goal.kind.rawValue):\($0)" } ?? "goal:\(goal.kind.rawValue)"
        addNews(.milestone, subject: subject, amount: goal.reward)
    }
}
