import SwiftUI
import CoreCatalog
import CoreWorld

struct NewGameDraft {
    var regionID = "caribbean"
    var home = "SXM"
    var name = "Aurora Air"
    var code = "ZZ"
    var branding = Branding.starter
    var difficulty: Difficulty = .standard
    var starterID = "c208"
    var mode: GameMode = .normal
    var scenario: ScenarioID?
    /// The free-play choices, kept while a scenario is picked (a scenario sets its own home, aircraft and money), so going back
    /// to Free play gives them back (GameStep.swift).
    var freePlay = FreePlayChoice()

    /// The rules the airline is founded with: a scenario always plays Normal.
    var effectiveMode: GameMode { scenario == nil ? mode : .normal }
}

struct FreePlayChoice {
    var home = "SXM"
    var starterID = "c208"
    var mode: GameMode = .normal
    var difficulty: Difficulty = .standard
}

/// The new-airline wizard: where you start, what you are called, how you look, what you fly.
struct NewGameFlow: View {
    let store: SaveStore
    let onCancel: () -> Void
    let onStart: (World, Int) -> Void

    @State private var step: Int
    @State private var draft = NewGameDraft()
    @State private var problem: String?

    init(store: SaveStore, onCancel: @escaping () -> Void, onStart: @escaping (World, Int) -> Void, initialStep: Int = 0, scenario: ScenarioID? = nil) {
        self.store = store
        self.onCancel = onCancel
        self.onStart = onStart
        _step = State(initialValue: min(max(initialStep, 0), Self.titles.count - 1))
        var draft = NewGameDraft()
        if let scenario, let def = ScenarioDefinition.definition(scenario) {
            draft.scenario = scenario
            draft.home = def.home
            draft.starterID = def.starterTypeID
            draft.difficulty = def.difficulty
        }
        _draft = State(initialValue: draft)
    }

    private static let titles = ["Game", "Region", "Base", "Airline", "Look", "Aircraft"]
    /// The step where the airline is named; a scenario skips straight to it (the scenario chooses the region and base).
    private static let identityStep = 3

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch step {
                case 0: GameStep(draft: $draft)
                case 1: RegionStep(draft: $draft)
                case 2: BaseStep(draft: $draft)
                case 3: IdentityStep(draft: $draft)
                case 4: BrandingEditor(branding: $draft.branding, airlineName: draft.name).padding(12)
                default: AircraftStep(draft: $draft, problem: problem)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background(PixelBackdrop())
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(Self.titles[step].uppercased()).pixelFont(16).foregroundStyle(Theme.accent)
            Spacer()
            ForEach(0..<Self.titles.count, id: \.self) { i in
                Rectangle().fill(i == step ? Theme.accent : (i < step ? Theme.accentDark : Theme.surfaceRaised)).frame(width: 18, height: 8)
            }
            Spacer()
            Text("Step \(step + 1) of \(Self.titles.count)").pixelFont(10.667).foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(step == 0 ? "Cancel" : "Back") {
                if step == 0 { onCancel() } else { step = step == Self.identityStep && draft.scenario != nil ? 0 : step - 1 }
            }.buttonStyle(SecondaryButtonStyle()).frame(width: 150)
            Spacer()
            if step < Self.titles.count - 1 {
                Button("Next") { step = step == 0 && draft.scenario != nil ? Self.identityStep : step + 1 }
                    .buttonStyle(PrimaryButtonStyle()).frame(width: 190).disabled(!canAdvance)
            } else {
                Button("Start airline") { start() }.buttonStyle(PrimaryButtonStyle()).frame(width: 220)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var canAdvance: Bool {
        if step == Self.identityStep { return draft.name.trimmingCharacters(in: .whitespaces).count >= 3 && (2...3).contains(draft.code.count) }
        return true
    }

    private func start() {
        let config = NewGameConfig(airlineName: draft.name.trimmingCharacters(in: .whitespaces), airlineCode: draft.code.uppercased(), homeAirport: draft.home,
                                   branding: draft.branding, difficulty: draft.difficulty, starterTypeID: draft.starterID, seed: UInt64.random(in: 1...UInt64.max),
                                   mode: draft.effectiveMode, scenario: draft.scenario)
        guard let slot = store.freeSlot() else {
            problem = "All \(SaveStore.slotCount) save slots are taken. Go back to the title screen and delete an airline under Continue first."
            return
        }
        do {
            let world = try World.newGame(config)
            store.prepareNewGame(slot: slot)
            onStart(world, slot)
        } catch let error as WorldError {
            problem = Messages.describe(error)
        } catch {
            problem = "Could not start the airline."
        }
    }
}

// MARK: - Steps (the region, home and aircraft steps are in StartSteps.swift)

struct IdentityStep: View {
    @Binding var draft: NewGameDraft
    @State private var suggestion = 0

    private static let names = ["Aurora Air", "Northern Wings", "Tundra Air", "Midnight Sun Air", "Caribou Air", "Frontier Wings", "Ice Road Air", "Lakeland Air",
                                "Otter Air", "Spruce Air", "Kestrel Air", "Longshore Air", "Highland Air", "Beacon Air", "Driftwood Air", "Bluff Air"]

    var body: some View {
        Page {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    // The suggestion button sits by the name it changes (it also sets a matching code).
                    HStack(alignment: .bottom, spacing: 12) {
                        PixelField(title: "Airline name (3 to 22 letters)", text: $draft.name, prompt: "Aurora Air")
                            // The pixel font only has plain letters, and long names do not fit the screens.
                            .onChange(of: draft.name) { _, new in
                                let clean = String(new.filter { $0.isASCII && ($0.isLetter || $0.isNumber || " -'&.".contains($0)) }.prefix(22))
                                if clean != new { draft.name = clean }
                            }
                        Button("Suggest a name") {
                            suggestion = (suggestion + 1) % Self.names.count
                            draft.name = Self.names[suggestion]
                            draft.code = Self.initials(Self.names[suggestion])
                        }
                        .buttonStyle(.small)
                    }
                    PixelField(title: "Code (2 or 3 letters)", text: $draft.code, prompt: "ZZ", capitalization: .characters)
                        .onChange(of: draft.code) { _, new in draft.code = String(new.uppercased().filter { $0.isASCII && $0.isLetter }.prefix(3)) }
                        .frame(maxWidth: 240, alignment: .leading)
                    Text("Your flights will be called \(draft.code.isEmpty ? "ZZ" : draft.code)101, \(draft.code.isEmpty ? "ZZ" : draft.code)102 and so on.")
                        .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    // Says why Next is greyed out.
                    if draft.name.trimmingCharacters(in: .whitespaces).count < 3 {
                        Text("The name needs at least 3 letters.").pixelFont(10.667).foregroundStyle(Theme.gold)
                    } else if draft.code.count < 2 {
                        Text("The code needs 2 or 3 letters.").pixelFont(10.667).foregroundStyle(Theme.gold)
                    }
                }
            }
        }
    }

    static func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}
