import SwiftUI
import CoreCatalog
import CoreWorld

struct NewGameDraft {
    var regionID = "arctic-canada"
    var home = "YEV"
    var name = "Aurora Air"
    var code = "ZZ"
    var branding = Branding.starter
    var difficulty: Difficulty = .standard
    var starterID = "c208"
    var mode: GameMode = .normal
    var scenario: ScenarioID?
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
                                   mode: draft.scenario == nil ? draft.mode : .normal, scenario: draft.scenario)
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

// MARK: - Steps

struct RegionStep: View {
    @Binding var draft: NewGameDraft

    var body: some View {
        Page {
            Text("Every airline starts small, far from the big cities. Where will yours begin?").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            ForEach(StartRegions.all) { region in
                let selected = region.id == draft.regionID
                Button {
                    draft.regionID = region.id
                    draft.home = region.headquarters[0]
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(region.name.uppercased()).pixelFont(13.333).foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                            Spacer()
                            if selected { Tag(text: "Selected", color: Theme.good) }
                        }
                        Text(region.blurb).pixelFont(10.667).foregroundStyle(Theme.textMuted).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
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

enum HomeStats {
    @MainActor private static var cache: [String: Int] = [:]

    /// How many other airports lie within 600 km: a rough measure of how much there is to fly to.
    @MainActor static func neighbours(_ code: String) -> Int {
        if let hit = cache[code] { return hit }
        guard let home = AirportCatalog.airport(code) else { return 0 }
        let count = AirportCatalog.all.filter { $0.code != code && $0.distanceKm(to: home) <= 600 }.count
        cache[code] = count
        return count
    }
}

struct BaseStep: View {
    @Binding var draft: NewGameDraft

    var body: some View {
        let region = StartRegions.region(draft.regionID)
        Page {
            Text("Choose your home airport. It is where your first aircraft lives.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            ForEach(region?.headquarters ?? [], id: \.self) { code in
                if let airport = AirportCatalog.airport(code) {
                    let selected = code == draft.home
                    Button { draft.home = code } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(airport.label.uppercased()).pixelFont(13.333).foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                                Spacer()
                                if selected { Tag(text: "Selected", color: Theme.good) }
                            }
                            Text(airport.name).pixelFont(10.667).foregroundStyle(Theme.textMuted)
                            HStack(spacing: 12) {
                                Text("People nearby \(Format.people(airport.population))")
                                Text("Runway \(Format.number(airport.runwayFt)) ft \(airport.surface == .gravel ? "gravel" : (airport.surface == .water ? "water" : "paved"))")
                                Text("\(HomeStats.neighbours(code)) airports within 600 km")
                            }
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
}

struct IdentityStep: View {
    @Binding var draft: NewGameDraft
    @State private var suggestion = 0

    private static let names = ["Aurora Air", "Northern Wings", "Tundra Air", "Midnight Sun Air", "Caribou Air", "Frontier Wings", "Ice Road Air", "Lakeland Air",
                                "Otter Air", "Spruce Air", "Kestrel Air", "Longshore Air", "Highland Air", "Beacon Air", "Driftwood Air", "Bluff Air"]

    var body: some View {
        Page {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    PixelField(title: "Airline name", text: $draft.name, prompt: "Aurora Air")
                        // The pixel font only has plain letters, and long names do not fit the screens.
                        .onChange(of: draft.name) { _, new in
                            let clean = String(new.filter { $0.isASCII && ($0.isLetter || $0.isNumber || " -'&.".contains($0)) }.prefix(22))
                            if clean != new { draft.name = clean }
                        }
                    HStack(spacing: 12) {
                        PixelField(title: "Code (2 or 3 letters)", text: $draft.code, prompt: "ZZ", capitalization: .characters)
                            .onChange(of: draft.code) { _, new in draft.code = String(new.uppercased().filter { $0.isASCII && $0.isLetter }.prefix(3)) }
                        Button("Suggest a name") {
                            suggestion = (suggestion + 1) % Self.names.count
                            draft.name = Self.names[suggestion]
                            draft.code = Self.initials(Self.names[suggestion])
                        }.buttonStyle(.small)
                    }
                    Text("Your flights will be called \(draft.code.isEmpty ? "ZZ" : draft.code)101, \(draft.code.isEmpty ? "ZZ" : draft.code)102 and so on.")
                        .pixelFont(10.667).foregroundStyle(Theme.textMuted)
                }
            }
        }
    }

    static func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

struct AircraftStep: View {
    @Binding var draft: NewGameDraft
    let problem: String?

    var body: some View {
        let offers = World.starterOffers(home: draft.home, difficulty: draft.difficulty).filter { draft.scenario == nil || $0.typeID == draft.starterID }
        Page {
            Text("Your starting money and your first aircraft. A bigger aircraft carries more but costs more to run.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            Text("Starting money \(Format.dollars(draft.difficulty.startingBudget))").pixelFont(13.333).foregroundStyle(Theme.textPrimary)
            if let problem { Text(problem).pixelFont(10.667).foregroundStyle(Theme.bad) }
            ForEach(offers) { offer in
                if let type = AircraftCatalog.type(offer.typeID) {
                    let selected = offer.typeID == draft.starterID
                    Button { draft.starterID = offer.typeID } label: {
                        HStack(spacing: 12) {
                            AircraftSpriteView(family: type.family, branding: draft.branding, pixel: 2).frame(width: 120, alignment: .center)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(type.displayName.uppercased()).pixelFont(13.333).foregroundStyle(selected ? Theme.accent : Theme.textPrimary).lineLimit(1)
                                Text("\(type.seats) seats - \(Format.number(type.rangeKm)) km range - \(Int(offer.ageYears)) years old").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                                Text("Price \(Format.dollars(offer.price)) - left over \(Format.dollars(draft.difficulty.startingBudget - offer.price))").pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                            }
                            Spacer()
                            if selected { Tag(text: "Selected", color: Theme.good) }
                        }
                        .padding(10)
                        .background(PixelPanel(fill: selected ? Theme.surfaceRaised : Theme.surface, border: selected ? Theme.accent : Theme.panelBorder))
                    }
                    .buttonStyle(.tap)
                    .accessibilitySelected(selected)
                }
            }
            if offers.isEmpty { EmptyNote("Nothing in your price range can use this airport. Pick an easier start.") }
        }
        .onAppear { fixSelection() }
    }

    private func fixSelection() {
        guard draft.scenario == nil else { return }
        let offers = World.starterOffers(home: draft.home, difficulty: draft.difficulty)
        if !offers.contains(where: { $0.typeID == draft.starterID }), let first = offers.first(where: { $0.typeID == "c208" }) ?? offers.first {
            draft.starterID = first.typeID
        }
    }

    static func name(_ d: Difficulty) -> String {
        switch d {
        case .easy: "Easy"
        case .standard: "Standard"
        case .hard: "Hard"
        }
    }
}
