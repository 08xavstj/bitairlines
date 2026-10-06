import SwiftUI
import CoreWorld

/// This week's goal: what to do, how far along it is, and the bonus for meeting it.
struct WeeklyGoalCard: View {
    let world: World
    /// With a session, a met goal offers the optional ad that pays the bonus again.
    var session: GameSession? = nil

    var body: some View {
        if let goal = world.ops.weeklyGoal {
            let progress = min(world.weeklyGoalProgress, goal.target)
            // Met shows at once; the bonus itself is paid at the next landing or midnight.
            let met = goal.done || world.weeklyGoalProgress >= goal.target
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("THIS WEEK").pixelFont(13.333).foregroundStyle(Theme.accent)
                        Spacer()
                        if met { Tag(text: "Done", color: Theme.good) } else { Tag(text: "Bonus \(Format.compactMoney(goal.reward))", color: Theme.gold) }
                    }
                    Text(WeeklyGoalCard.describe(goal)).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Theme.surfaceRaised)
                            Rectangle().fill(met ? Theme.good : Theme.accent)
                                .frame(width: geo.size.width * CGFloat(progress) / CGFloat(max(1, goal.target)))
                        }
                    }
                    .frame(height: 8)
                    Text("\(WeeklyGoalCard.amount(goal.kind, progress)) of \(WeeklyGoalCard.amount(goal.kind, goal.target))\(goal.place == nil ? "" : " landed there"). Goals met: \(world.ops.goalsCompleted).")
                        .pixelFont(10.667).foregroundStyle(Theme.textMuted)
                    if let session, let paid = world.goalToDouble {
                        // Last week's goal, met late, can still have its bonus paid again until this week's is met.
                        if !goal.done && world.rewardOffer(.doubleGoalBonus, realDay: RealDay.today()) != nil {
                            Text("Last week's goal was met: bonus of \(Format.compactMoney(paid.reward)) paid.")
                                .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        }
                        RewardButton(session: session, kind: .doubleGoalBonus)
                    }
                    if let real = world.ops.realWeekGoal { RealWeekGoalSection(world: world, goal: real) }
                }
            }
        }
    }

    static func describe(_ goal: WeeklyGoal) -> String {
        if let place = goal.place {
            let name = Place.name(place)
            switch goal.kind {
            case .freightKg: return "Deliver \(Format.number(goal.target)) kg of freight to \(name) before Monday."
            default: return "Carry \(Format.number(goal.target)) passengers to \(name) before Monday."
            }
        }
        switch goal.kind {
        case .passengers: return "Carry \(Format.number(goal.target)) passengers before Monday."
        case .freightKg: return "Move \(Format.number(goal.target)) kg of freight before Monday."
        case .flights: return "Fly \(Format.number(goal.target)) flights before Monday."
        case .revenue: return "Earn \(Format.compactMoney(goal.target)) from flights before Monday."
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
