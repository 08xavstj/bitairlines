import SwiftUI
import CoreWorld

/// The real-week goal, shown under the game-week goal on the same card: Monday to Sunday on the player's own calendar.
struct RealWeekGoalSection: View {
    let world: World
    let goal: WeeklyGoal

    var body: some View {
        let progress = min(world.realWeekGoalProgress, goal.target)
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Theme.separator).frame(height: 1).padding(.vertical, 2)
            HStack {
                Text("THIS REAL WEEK").pixelFont(13.333).foregroundStyle(Theme.accent)
                Spacer()
                if goal.done { Tag(text: "Done", color: Theme.good) } else { Tag(text: "Bonus \(Format.compactMoney(goal.reward))", color: Theme.gold) }
            }
            Text(WeeklyGoalCard.describe(goal).replacingOccurrences(of: "before Monday", with: "by Sunday, real time"))
                .pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.surfaceRaised)
                    Rectangle().fill(goal.done ? Theme.good : Theme.accent)
                        .frame(width: geo.size.width * CGFloat(progress) / CGFloat(max(1, goal.target)))
                }
            }
            .frame(height: 8)
            Text("\(WeeklyGoalCard.amount(goal.kind, progress)) of \(WeeklyGoalCard.amount(goal.kind, goal.target)) landed there. \(CalendarWords.days(world.realWeekDaysLeft)) left. Met so far: \(world.ops.realWeekGoalsMet).")
                .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
        }
    }
}
