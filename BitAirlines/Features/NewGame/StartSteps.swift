import SwiftUI
import CoreCatalog
import CoreWorld

// The wizard's where-and-what steps: the region, the home airport and the first aircraft. Each home and each aircraft says what its
// best first route would earn (StartOutlook.swift), so the biggest choice of the game is made with numbers in front of the player.

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

/// The home airport, with what the default first aircraft would earn from each.
struct BaseStep: View {
    @Binding var draft: NewGameDraft
    /// Per home: the aircraft it was judged for and what it would earn.
    @State private var outlooks: [String: HomeOutlook] = [:]

    struct HomeOutlook {
        var typeID: String
        var outlook: StartOutlook
    }

    var body: some View {
        let codes = StartRegions.region(draft.regionID)?.headquarters ?? []
        Page {
            Text("Choose your home airport. It is where your first aircraft lives.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            ForEach(codes, id: \.self) { code in
                if let airport = AirportCatalog.airport(code) {
                    let selected = code == draft.home
                    Button { draft.home = code } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(airport.label.uppercased()).pixelFont(13.333).foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                                Spacer()
                                if selected { Tag(text: "Selected", color: Theme.good) }
                            }
                            Text(airport.name).pixelFont(10.667).foregroundStyle(Theme.textMuted).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            // One text, so it wraps as a whole instead of squeezing three columns.
                            Text(BaseStep.facts(airport, openNearby: outlooks[code]?.outlook.openNearby))
                                .pixelFont(10.667).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            outlookLine(code)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(PixelPanel(fill: selected ? Theme.surfaceRaised : Theme.surface, border: selected ? Theme.accent : Theme.panelBorder))
                    }
                    .buttonStyle(.tap)
                    .accessibilitySelected(selected)
                }
            }
            Text(StartOutlookWords.headOffice).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
        }
        .task(id: "\(draft.regionID)|\(draft.difficulty.rawValue)|\(draft.effectiveMode.rawValue)") { await load(codes) }
    }

    @ViewBuilder private func outlookLine(_ code: String) -> some View {
        if let item = outlooks[code] {
            let name = AircraftCatalog.type(item.typeID)?.name
            Text(StartOutlookWords.line(home: code, outlook: item.outlook, typeName: name))
                .pixelFont(10.667).foregroundStyle(item.outlook.destination == nil ? Theme.gold : Theme.good)
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Working out the best first route...").pixelFont(10.667).foregroundStyle(Theme.textMuted)
        }
    }

    @MainActor private func load(_ codes: [String]) async {
        let difficulty = draft.difficulty, mode = draft.effectiveMode
        for code in codes {
            guard let typeID = StartOutlooks.defaultStarter(home: code, difficulty: difficulty, mode: mode),
                  let outlook = await StartOutlooks.load(home: code, typeID: typeID, difficulty: difficulty, mode: mode) else { continue }
            outlooks[code] = HomeOutlook(typeID: typeID, outlook: outlook)
        }
    }

    /// "People nearby 63K. Runway 7,546 ft paved. 6 airports open to you within 600 km."
    static func facts(_ airport: Airport, openNearby: Int?) -> String {
        let surface = airport.surface == .gravel ? "gravel" : (airport.surface == .water ? "water" : "paved")
        let nearby = openNearby.map { " \($0) airport\($0 == 1 ? "" : "s") open to you within 600 km." } ?? ""
        return "People nearby \(Format.people(airport.population)). Runway \(Format.number(airport.runwayFt)) ft \(surface)." + nearby
    }
}

/// Starting money and the first aircraft, each with what its best first route from home would earn.
struct AircraftStep: View {
    @Binding var draft: NewGameDraft
    let problem: String?
    /// Per aircraft type, for the home shown.
    @State private var outlooks: [String: StartOutlook] = [:]

    var body: some View {
        let offers = World.starterOffers(home: draft.home, difficulty: draft.difficulty, mode: draft.effectiveMode)
            .filter { draft.scenario == nil || $0.typeID == draft.starterID }
        Page {
            Text("Your starting money and your first aircraft. A bigger aircraft carries more but costs more to run.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            Text("Starting money \(Format.dollars(draft.difficulty.startingBudget))").pixelFont(13.333).foregroundStyle(Theme.textPrimary)
            if let problem { Text(problem).pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true) }
            ForEach(offers) { offer in
                if let type = AircraftCatalog.type(offer.typeID) {
                    let selected = offer.typeID == draft.starterID
                    Button { draft.starterID = offer.typeID } label: {
                        HStack(spacing: 12) {
                            AircraftSpriteView(family: type.family, branding: draft.branding, pixel: 2).frame(width: 120, alignment: .center)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(type.displayName.uppercased()).pixelFont(13.333).foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                Text("\(type.seats) seats - \(Format.number(type.rangeKm)) km range - \(Int(offer.ageYears)) years old").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                Text("Price \(Format.dollars(offer.price)) - left over \(Format.dollars(draft.difficulty.startingBudget - offer.price))").pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                outlookLine(offer.typeID)
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
            if offers.isEmpty {
                EmptyNote("Nothing in your price range can use this airport. Pick an easier start.")
            } else {
                Text(StartOutlookWords.headOffice).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { fixSelection() }
        .task(id: "\(draft.home)|\(draft.difficulty.rawValue)|\(draft.effectiveMode.rawValue)") { await load(offers.map(\.typeID)) }
    }

    @ViewBuilder private func outlookLine(_ typeID: String) -> some View {
        if let outlook = outlooks[typeID] {
            Text(StartOutlookWords.line(home: draft.home, outlook: outlook))
                .pixelFont(10.667).foregroundStyle(outlook.destination == nil ? Theme.gold : Theme.good)
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Working out the best first route...").pixelFont(10.667).foregroundStyle(Theme.textMuted)
        }
    }

    @MainActor private func load(_ typeIDs: [String]) async {
        let home = draft.home, difficulty = draft.difficulty, mode = draft.effectiveMode
        outlooks = [:]
        for typeID in typeIDs {
            if let outlook = await StartOutlooks.load(home: home, typeID: typeID, difficulty: difficulty, mode: mode) { outlooks[typeID] = outlook }
        }
    }

    private func fixSelection() {
        guard draft.scenario == nil else { return }
        let offers = World.starterOffers(home: draft.home, difficulty: draft.difficulty, mode: draft.effectiveMode)
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
