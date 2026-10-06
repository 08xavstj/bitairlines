import SwiftUI
import CoreCatalog
import CoreWorld

/// The airline's bases: the home apron, what has been built where, and slots held at busy airports.
struct BasesScreen: View {
    let session: GameSession
    @State private var building: String?

    var body: some View {
        let world = session.world
        Page {
            // The Bases sub-tab above already names the screen, so no second title here.
            Text("Upkeep for all bases: \(Format.dollars(world.baseUpkeepPerDay)) a day").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            HomeApron(session: session)
                .frame(height: 170)
                .background(PixelPanel(fill: Theme.surface))
            DeparturesBoard(world: world)
            if world.ops.bases.isEmpty {
                EmptyNote("No bases yet. Build at home, or tap an airport on the Map and choose Build here.")
            }
            ForEach(world.ops.bases) { base in
                Card {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Place.name(base.airport).uppercased()).pixelFont(13.333).foregroundStyle(Theme.accent)
                                .fixedSize(horizontal: false, vertical: true)
                            if base.facilities.isEmpty {
                                Text("Nothing built here yet.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                            } else {
                                FlowTags(texts: base.facilities.map { Words.name($0) })
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button { building = base.airport } label: { HangarButtonText("Build more") }.buttonStyle(.small)
                    }
                }
            }
            if !world.ops.bases.contains(where: { $0.airport == world.airline.home }) {
                Button { building = world.airline.home } label: { HangarButtonText("Build at \(Place.name(world.airline.home))") }.buttonStyle(.smallProminent)
            }
            if session.world.airline.level >= GameSection.lateLevel { SlotsCard(session: session) }
        }
        .sheet(item: Binding(get: { building.map { CodeSheet(id: $0) } }, set: { building = $0?.id })) { sheet in
            BuildSheet(session: session, code: sheet.id)
        }
    }
}

struct CodeSheet: Identifiable { let id: String }

/// A row of small tags that wraps onto two lines when it has to.
struct FlowTags: View {
    let texts: [String]
    var body: some View {
        let rows = stride(from: 0, to: texts.count, by: 3).map { Array(texts[$0..<min($0 + 3, texts.count)]) }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) { ForEach(row, id: \.self) { Tag(text: $0, color: Theme.good) } }
            }
        }
    }
}

/// What can be built at one airport, with the price, the upkeep and why not (if not).
struct BuildSheet: View {
    let session: GameSession
    let code: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let world = session.world
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(title: "Build at \(Place.name(code))") { Button { dismiss() } label: { HangarButtonText("Close") }.buttonStyle(.small) }
            HangarNotice(session: session)
            ScrollView {
                VStack(spacing: 8) {
                    if let airport = AirportCatalog.airport(code) {
                        ForEach(Facility.allCases.filter { $0 != .hubTerminal || world.airline.level >= GameSection.lateLevel }, id: \.self) { facility in
                            let built = world.ops.bases.first { $0.airport == code }?.has(facility) == true
                            let problem = world.facilityProblem(facility, at: code)
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Words.name(facility).uppercased()).pixelFont(13.333).foregroundStyle(built ? Theme.good : Theme.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(Words.explain(facility)).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                                    Text("\(Format.dollars(world.facilityPrice(facility, at: airport))) to build, \(Format.dollars(world.facilityUpkeep(facility, at: airport))) a day to keep")
                                        .pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                                    if let problem, !built, problem != .alreadyBuilt {
                                        Text(Messages.describe(problem)).pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if built {
                                    Tag(text: "Built", color: Theme.good)
                                } else {
                                    Button { session.perform(sound: .coin) { try $0.build(facility, at: code) } } label: { HangarButtonText("Build") }
                                        .buttonStyle(.smallProminent).disabled(problem != nil)
                                }
                            }
                            .padding(12).background(PixelPanel())
                        }
                        if world.needsSlots(airport) { SlotRow(session: session, airport: airport) }
                    }
                }
            }
        }
        .padding(16)
        .screenBackground()
        .onAppear { session.notice = nil }
    }
}

/// Slots held at one busy airport, with buy and sell.
struct SlotRow: View {
    let session: GameSession
    let airport: Airport

    var body: some View {
        let world = session.world
        let held = world.slotsHeld(at: airport.code)
        let scheduled = world.slotsScheduled(at: airport.code)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SLOTS AT \(airport.label.uppercased())").pixelFont(13.333).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("You hold \(held) a day; your routes schedule \(scheduled). \(Format.dollars(world.slotPrice(at: airport))) per daily slot.")
                    .pixelFont(10.667).foregroundStyle(scheduled > held ? Theme.gold : Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { session.perform(sound: .coin) { try $0.buySlots(at: airport.code, count: 1) } } label: { HangarButtonText("Buy 1") }.buttonStyle(.smallProminent)
            if held > 0 {
                Button { session.perform(sound: .coin) { try $0.sellSlots(at: airport.code, count: 1) } } label: { HangarButtonText("Sell 1") }.buttonStyle(.small)
            }
        }
        .padding(12).background(PixelPanel())
    }
}

/// Every busy airport where the airline holds or needs slots.
struct SlotsCard: View {
    let session: GameSession

    var body: some View {
        let world = session.world
        let codes = Array(Set(world.ops.slots.map(\.airport) + world.routes.flatMap { $0.stops }.filter { code in
            AirportCatalog.airport(code).map { world.needsSlots($0) } ?? false
        })).sorted()
        if !codes.isEmpty {
            SectionTitle("Slots")
            ForEach(codes, id: \.self) { code in
                if let airport = AirportCatalog.airport(code) { SlotRow(session: session, airport: airport) }
            }
            Text("Busy airports ration departures. Beyond your slots, flights wait for the next day.")
                .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
        }
    }
}
