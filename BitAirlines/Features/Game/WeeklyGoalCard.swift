import SwiftUI
import CoreWorld

/// This week's goal: what to do, how far along it is, and the bonus for meeting it.
struct WeeklyGoalCard: View {
    let world: World

    var body: some View {
        if let goal = world.ops.weeklyGoal {
            let progress = min(world.weeklyGoalProgress, goal.target)
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("THIS WEEK").pixelFont(13.333).foregroundStyle(Theme.accent)
                        Spacer()
                        if goal.done { Tag(text: "Done", color: Theme.good) } else { Tag(text: "Bonus \(Format.compactMoney(goal.reward))", color: Theme.gold) }
                    }
                    Text(WeeklyGoalCard.describe(goal)).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Theme.surfaceRaised)
                            Rectangle().fill(goal.done ? Theme.good : Theme.accent)
                                .frame(width: geo.size.width * CGFloat(progress) / CGFloat(max(1, goal.target)))
                        }
                    }
                    .frame(height: 8)
                    Text("\(WeeklyGoalCard.amount(goal.kind, progress)) of \(WeeklyGoalCard.amount(goal.kind, goal.target)). Goals met: \(world.ops.goalsCompleted).")
                        .pixelFont(10.667).foregroundStyle(Theme.textMuted)
                }
            }
        }
    }

    static func describe(_ goal: WeeklyGoal) -> String {
        switch goal.kind {
        case .passengers: "Carry \(Format.number(goal.target)) passengers before Monday."
        case .freightKg: "Move \(Format.number(goal.target)) kg of freight before Monday."
        case .flights: "Fly \(Format.number(goal.target)) flights before Monday."
        case .revenue: "Earn \(Format.compactMoney(goal.target)) from flights before Monday."
        }
    }

    static func amount(_ kind: WeeklyGoalKind, _ n: Int) -> String {
        switch kind {
        case .passengers, .flights: Format.number(n)
        case .freightKg: "\(Format.number(n)) kg"
        case .revenue: Format.compactMoney(n)
        }
    }
}
