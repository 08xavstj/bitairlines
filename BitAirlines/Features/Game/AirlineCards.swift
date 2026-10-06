import SwiftUI
import CoreCatalog
import CoreWorld

/// The rules this game runs on, the perks picked so far, and how punctual the airline is.
struct RulesCard: View {
    let world: World

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("RULES AND PERKS").pixelFont(13.333).foregroundStyle(Theme.accent)
                KeyValueRow("Mode", Words.name(world.ops.mode))
                Text(Words.explain(world.ops.mode)).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                KeyValueRow("On time", Format.percent(world.ops.onTime.share), color: world.ops.onTime.share >= 0.85 ? Theme.good : Theme.gold)
                if world.ops.perks.isEmpty {
                    Text("Each new certificate level lets you pick a perk.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                }
                ForEach(world.ops.perks, id: \.self) { perk in
                    KeyValueRow(Words.name(perk), Words.explain(perk), color: Theme.good)
                }
            }
        }
    }
}

/// Every airline by passengers a year.
struct RankingsCard: View {
    let world: World

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("RANKINGS").pixelFont(13.333).foregroundStyle(Theme.accent)
                HStack {
                    Text("Airline").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Routes").frame(width: 70, alignment: .trailing)
                    Text("Aircraft").frame(width: 80, alignment: .trailing)
                    Text("People a year").frame(width: 130, alignment: .trailing)
                }
                .pixelFont(10.667).foregroundStyle(Theme.textMuted)
                ForEach(Array(world.rankings.enumerated()), id: \.offset) { n, row in
                    HStack {
                        Text("\(n + 1). \(row.name)").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(row.routes)").frame(width: 70, alignment: .trailing)
                        Text("\(row.aircraft)").frame(width: 80, alignment: .trailing)
                        Text(Format.number(row.passengersPerYear)).frame(width: 130, alignment: .trailing)
                    }
                    .pixelFont(10.667).foregroundStyle(row.isPlayer ? Theme.gold : Theme.textPrimary)
                }
                Text("Other airlines are estimated from their routes.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            }
        }
    }
}

/// Progress towards the scenario goal, and the medal once it is won.
struct ScenarioCard: View {
    let world: World

    var body: some View {
        if let state = world.ops.scenario, let def = ScenarioDefinition.definition(state.id) {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SCENARIO: \(Words.name(state.id).uppercased())").pixelFont(13.333).foregroundStyle(Theme.gold)
                    Text(Words.goal(def)).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    StatBar(label: "Progress", value: state.progress * 100, color: Theme.gold, valueText: Format.percent(state.progress))
                    if let medal = state.medal {
                        Text("Done: \(Words.name(medal)) medal.").pixelFont(13.333).foregroundStyle(Theme.good)
                    } else if state.failed {
                        Text("The deadline passed. You can keep flying.").pixelFont(10.667).foregroundStyle(Theme.bad)
                    } else {
                        let left = state.deadlineDay - world.clock.dayIndex
                        Text("\(left) days left. Finish in the first 60% of the time for gold, 80% for silver.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
