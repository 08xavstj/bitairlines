import SwiftUI
import CoreCatalog
import CoreWorld

enum FleetText {
    static func status(_ plane: Aircraft, in world: World) -> (text: String, color: Color) {
        switch plane.status {
        case .idle:
            return ("Parked at \(Place.name(plane.location))", Theme.textMuted)
        case .boarding(let until):
            return (until > world.clock.minute + 120 ? "Waiting at \(Place.name(plane.location)) until \(Format.time(GameClock(minute: until)))" : "Boarding at \(Place.name(plane.location))", Theme.info)
        case .flying(let until):
            let to = Place.name(plane.flight?.to ?? "?")
            return ("\(Place.name(plane.location)) to \(to), lands \(Format.time(GameClock(minute: until)))", Theme.good)
        case .maintenance(let until):
            return ("In the hangar until \(Format.date(GameClock(minute: until).date))", Theme.gold)
        case .grounded:
            return ("Grounded: needs your decision", Theme.bad)
        case .onOrder(let until):
            return ("Arrives \(Format.date(GameClock(minute: until).date)) at \(Format.time(GameClock(minute: until)))", Theme.gold)
        }
    }

    static func routeName(_ plane: Aircraft, in world: World) -> String {
        if let jobID = plane.jobID, let job = world.ops.jobs.first(where: { $0.id == jobID }) {
            return "On a job: \(Words.name(job.kind).lowercased()) to \(Place.name(job.to))"
        }
        guard let id = plane.routeID, let route = world.routes.first(where: { $0.id == id }) else { return "No route" }
        return route.name
    }
}

struct FleetScreen: View {
    let session: GameSession
    @State private var openID: Int?
    @State private var showPilots = FleetScreen.startOnPilots

    var body: some View {
        let world = session.world
        Page {
            ScreenHeader(title: "Fleet") {
                PixelChoice(options: [(label: "Aircraft", value: false), (label: "Pilots", value: true)], selection: $showPilots).frame(width: 220)
            }
            if showPilots {
                PilotsView(session: session)
            } else {
                aircraftList(world)
            }
        }
        .sheet(item: Binding(get: { openID.map { SheetID(id: $0) } }, set: { openID = $0?.id })) { sheet in
            AircraftSheet(session: session, aircraftID: sheet.id)
        }
    }

    private static var startOnPilots: Bool {
        #if DEBUG
        return Demo.screen == "pilots"
        #else
        return false
        #endif
    }

    @ViewBuilder private func aircraftList(_ world: World) -> some View {
            if world.aircraft.isEmpty { EmptyNote("You have no aircraft. Visit the Hangar to buy one.") }
            ForEach(world.aircraft) { plane in
                if let type = plane.type {
                    let status = FleetText.status(plane, in: world)
                    Button { openID = plane.id } label: {
                        HStack(spacing: 12) {
                            AircraftSpriteView(family: type.family, branding: plane.livery?.branding ?? world.airline.branding, pixel: 2).frame(width: 130)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(plane.registration).pixelFont(13.333).foregroundStyle(Theme.accent)
                                    Text(type.displayName).pixelFont(10.667).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                }
                                Text(status.text).pixelFont(10.667).foregroundStyle(status.color).lineLimit(1)
                                Text("Route: \(FleetText.routeName(plane, in: world))").pixelFont(10.667).foregroundStyle(Theme.textMuted).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                StatBar(label: "Condition", value: plane.condition, color: plane.condition < 50 ? Theme.bad : Theme.good).frame(width: 170)
                            }
                        }
                        .padding(10)
                        .background(PixelPanel())
                    }
                    .buttonStyle(.tap)
                }
            }
    }
}

struct SheetID: Identifiable { let id: Int }

/// One aircraft: facts, route assignment, special livery and sale.
struct AircraftSheet: View {
    let session: GameSession
    let aircraftID: Int
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSell = false
    @State private var editingLivery = false

    var body: some View {
        let world = session.world
        VStack(alignment: .leading, spacing: 10) {
            if let plane = world.aircraft.first(where: { $0.id == aircraftID }), let type = plane.type {
                ScreenHeader(title: plane.registration) { Button("Close") { dismiss() }.buttonStyle(.small) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Card {
                            HStack(alignment: .top, spacing: 14) {
                                AircraftSpriteView(family: type.family, branding: plane.livery?.branding ?? world.airline.branding, pixel: 3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(type.displayName).pixelFont(13.333).foregroundStyle(Theme.textPrimary)
                                    KeyValueRow("Seats", "\(type.seats)")
                                    KeyValueRow("Range", Format.km(Double(type.rangeKm)))
                                    KeyValueRow("Age", "\(Int(plane.ageYears(atDay: world.clock.dayIndex))) years")
                                    KeyValueRow("Flights", Format.number(plane.totalFlights))
                                    KeyValueRow("Worth", Format.dollars(world.saleValue(of: plane)))
                                }
                            }
                        }
                        SectionTitle("Crew and kit")
                        KitsCard(session: session, aircraftID: aircraftID)
                        SectionTitle("Route")
                        routePicker(plane: plane, type: type, world: world)
                        SectionTitle("Paint")
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(plane.livery == nil ? "Wearing the airline livery." : "Wearing the special livery \"\(plane.livery?.name ?? "")\".").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                                HStack(spacing: 8) {
                                    Button("Special livery") { editingLivery = true }.buttonStyle(.small)
                                    if plane.livery != nil { Button("Use airline livery") { session.perform { try $0.setLivery(aircraftID: aircraftID, livery: nil) } }.buttonStyle(.small) }
                                }
                            }
                        }
                        Button("Sell for \(Format.dollars(world.saleValue(of: plane)))") { confirmSell = true }.buttonStyle(.smallDanger)
                            .disabled(plane.routeID != nil || !plane.isDelivered)
                        if let notice = session.notice { Text(notice).pixelFont(10.667).foregroundStyle(Theme.gold) }
                    }
                }
            } else {
                ScreenHeader(title: "Aircraft") { Button("Close") { dismiss() }.buttonStyle(.small) }
                EmptyNote("This aircraft is gone.")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .screenBackground()
        .pixelConfirm("Sell this aircraft?", message: "The dealer pays less than it is worth.", confirm: "Sell", destructive: true, isPresented: $confirmSell) {
            if session.perform(sound: .coin, { _ = try $0.sell(aircraftID: aircraftID) }) { dismiss() }
        }
        .sheet(isPresented: $editingLivery) { LiverySheet(session: session, aircraftID: aircraftID) }
    }

    @ViewBuilder private func routePicker(plane: Aircraft, type: AircraftType, world: World) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                if world.routes.isEmpty { Text("No routes yet. Plan one on the Map.").pixelFont(10.667).foregroundStyle(Theme.textMuted) }
                ForEach(world.routes) { route in
                    let problem = world.fitProblem(type: type, route: route, kits: plane.kits)
                    let current = plane.routeID == route.id
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.name).pixelFont(13.333).foregroundStyle(current ? Theme.accent : Theme.textPrimary)
                            if let problem { Text(Messages.describe(problem)).pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true) }
                            else if !current { AssignOutlook(world: world, route: route, type: type) }
                        }
                        Spacer()
                        if current {
                            Button("Take off route") { session.perform { try $0.unassign(aircraftID: aircraftID) } }.buttonStyle(.small)
                        } else {
                            Button("Assign") { session.perform { try $0.assign(aircraftID: aircraftID, toRoute: route.id) } }.buttonStyle(.smallProminent)
                                .disabled(problem != nil || !plane.isDelivered)
                        }
                    }
                }
            }
        }
    }
}

/// Paint one aircraft differently from the rest of the fleet.
struct LiverySheet: View {
    let session: GameSession
    let aircraftID: Int
    @Environment(\.dismiss) private var dismiss
    @State private var branding: Branding = .starter
    @State private var name = "Special"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScreenHeader(title: "Special livery") {
                HStack(spacing: 8) {
                    Button("Cancel") { dismiss() }.buttonStyle(.small)
                    Button("Apply") {
                        session.perform { try $0.setLivery(aircraftID: aircraftID, livery: SpecialLivery(name: name, branding: branding)) }
                        dismiss()
                    }.buttonStyle(.smallProminent)
                }
            }
            PixelField(title: "Livery name", text: $name, prompt: "Retro")
            BrandingEditor(branding: $branding, airlineName: session.world.airline.name)
        }
        .padding(16)
        .screenBackground()
        .onAppear {
            if let plane = session.world.aircraft.first(where: { $0.id == aircraftID }) {
                branding = plane.livery?.branding ?? session.world.airline.branding
                name = plane.livery?.name ?? "Special"
            }
        }
    }
}
