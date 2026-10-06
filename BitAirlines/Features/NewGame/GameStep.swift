import SwiftUI
import CoreCatalog
import CoreWorld

/// The first step of a new airline: play freely (and choose the rules), or take on a scenario with a goal and a deadline.
struct GameStep: View {
    @Binding var draft: NewGameDraft

    var body: some View {
        Page {
            Text("Play freely, or take on a scenario with a goal and a deadline.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            PixelChoice(options: [(label: "Free play", value: false), (label: "Scenario", value: true)],
                        selection: Binding(get: { draft.scenario != nil }, set: { on in choose(on ? (draft.scenario ?? ScenarioID.allCases[0]) : nil) }))
            if draft.scenario == nil {
                SectionTitle("Rules")
                PixelChoice(options: GameMode.allCases.map { (label: Words.name($0), value: $0) }, selection: $draft.mode)
                Text(Words.explain(draft.mode)).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(ScenarioDefinition.all) { def in
                    let selected = def.id == draft.scenario
                    Button { choose(def.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(Words.name(def.id).uppercased()).pixelFont(13.333).foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                                Spacer()
                                if let medal = ScenarioRecords.best(def.id) { Tag(text: Words.name(medal), color: Theme.gold) }
                                if selected { Tag(text: "Selected", color: Theme.good) }
                            }
                            Text(Words.goal(def)).pixelFont(10.667).foregroundStyle(Theme.textMuted).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Text("\(def.deadlineDays) days. Starts at \(Place.name(def.home)) with a \(AircraftCatalog.type(def.starterTypeID)?.name ?? def.starterTypeID).")
                                .pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(PixelPanel(fill: selected ? Theme.surfaceRaised : Theme.surface, border: selected ? Theme.accent : Theme.panelBorder))
                    }
                    .buttonStyle(.tap)
                    .accessibilitySelected(selected)
                }
            }
        }
    }

    /// Picks a scenario (or free play): a scenario decides the home, the first aircraft and the money.
    private func choose(_ id: ScenarioID?) {
        draft.scenario = id
        guard let id, let def = ScenarioDefinition.definition(id) else { return }
        draft.home = def.home
        draft.starterID = def.starterTypeID
        draft.difficulty = def.difficulty
        draft.mode = .normal
    }
}

/// The best medal won in each scenario, kept on the phone.
enum ScenarioRecords {
    private static func key(_ id: ScenarioID) -> String { "scenario.best.\(id.rawValue)" }

    static func best(_ id: ScenarioID, defaults: UserDefaults = .standard) -> Medal? {
        defaults.string(forKey: key(id)).flatMap { Medal(rawValue: $0) }
    }

    /// Keeps the medal if it beats the one already won.
    static func record(_ medal: Medal, for id: ScenarioID, defaults: UserDefaults = .standard) {
        let order: [Medal] = [.gold, .silver, .bronze]
        if let old = best(id, defaults: defaults), let a = order.firstIndex(of: old), let b = order.firstIndex(of: medal), a <= b { return }
        defaults.set(medal.rawValue, forKey: key(id))
    }
}
