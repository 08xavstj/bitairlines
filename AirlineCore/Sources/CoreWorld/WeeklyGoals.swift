// CoreWorld/WeeklyGoals.swift: one goal each game week (carry more people, move more freight, fly more, earn more), set a little
// above what the airline did the week before. Meeting it pays a bonus and counts towards the Game Center goals leaderboard.
// The kind follows the week number (no random draw), so the other systems' random streams stay the same.
import CoreCatalog

public enum WeeklyGoalKind: String, Sendable, Hashable, Codable, CaseIterable {
    case passengers, freightKg, flights, revenue
}

public struct WeeklyGoal: Sendable, Hashable, Codable {
    /// Game week number (day index / 7) the goal belongs to.
    public var week: Int
    public var kind: WeeklyGoalKind
    public var target: Int
    /// The airline's running total when the week began; progress is the total now minus this.
    public var baseline: Int
    /// Every kind's running total when the week began (by kind name), so next week's goal knows what this week achieved.
    public var startTotals: [String: Int]
    public var reward: Int
    public var done: Bool
}

// MARK: Weekly goals
extension Tuning {
    /// The goal is last week's result times this, at least the floor below.
    public static let weeklyGoalStretch = 1.2
    public static let weeklyGoalFloor: [WeeklyGoalKind: Int] = [.passengers: 30, .freightKg: 800, .flights: 10, .revenue: 10_000]
    /// The bonus is this share of last week's revenue, at least the minimum.
    public static let weeklyGoalRewardShare = 0.15
    public static let weeklyGoalMinimumReward = 5_000
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
        return max(0, goalTotal(goal.kind) - goal.baseline)
    }

    /// Sets the goal for the week that starts now. Called when a game starts and every Monday.
    mutating func startWeeklyGoal() {
        let week = clock.dayIndex / 7
        let kinds = WeeklyGoalKind.allCases
        let kind = kinds[week % kinds.count]
        // What the airline did last week in this kind of goal, and what it earned.
        let lastWeek = ops.weeklyGoal.flatMap { $0.startTotals[kind.rawValue] }.map { goalTotal(kind) - $0 } ?? 0
        let lastRevenue = books.suffix(7).reduce(0) { $0 + $1.revenue }
        let floor = Tuning.weeklyGoalFloor[kind] ?? 1
        let target = max(floor, Int((Double(lastWeek) * Tuning.weeklyGoalStretch).rounded()))
        let reward = max(Tuning.weeklyGoalMinimumReward, Int(Double(lastRevenue) * Tuning.weeklyGoalRewardShare))
        var totals: [String: Int] = [:]
        for k in kinds { totals[k.rawValue] = goalTotal(k) }
        ops.weeklyGoal = WeeklyGoal(week: week, kind: kind, target: target, baseline: goalTotal(kind), startTotals: totals, reward: reward, done: false)
    }

    /// Pays the bonus once the goal is met. Checked every day.
    mutating func checkWeeklyGoal() {
        guard let goal = ops.weeklyGoal, !goal.done, weeklyGoalProgress >= goal.target else { return }
        ops.weeklyGoal?.done = true
        ops.goalsCompleted += 1
        airline.cash += goal.reward
        addNews(.milestone, subject: "goal:\(goal.kind.rawValue)", amount: goal.reward)
    }
}
