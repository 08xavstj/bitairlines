import SwiftUI
import CoreCatalog
import CoreWorld

enum FleetText {
    static func status(_ plane: Aircraft, in world: World) -> (text: String, color: Color) {
        switch plane.status {
        case .idle:
            if plane.awaitingRestoration { return ("Barn find at \(Place.name(plane.location)): needs restoring", Theme.gold) }
            return ("Parked at \(Place.name(plane.location))", Theme.textMuted)
        case .boarding(let until):
            return (until > world.clock.minute + 120 ? "Waiting at \(Place.name(plane.location)) until \(Format.when(GameClock(minute: until), now: world.clock))" : "Boarding at \(Place.name(plane.location))", Theme.info)
        case .flying(let until):
            let to = Place.name(plane.flight?.to ?? "?")
            return ("\(Place.name(plane.location)) to \(to), lands \(Format.time(GameClock(minute: until)))", Theme.good)
        case .maintenance(let until):
            let date = Format.date(GameClock(minute: until).date)
            if plane.restoration?.untilMinute == until { return ("Being restored until \(date)", Theme.gold) }
            if plane.lastHeavyCheckMinute == until { return ("Heavy check until \(date)", Theme.gold) }
            return ("In the hangar until \(date)", Theme.gold)
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
        let names = routeNames(plane, in: world)
        return names.isEmpty ? "No route" : names.joined(separator: ", ")
    }

    /// The names of every route the aircraft flies, the current one first.
    static func routeNames(_ plane: Aircraft, in world: World) -> [String] {
        plane.allRouteIDs.compactMap { id in world.routes.first { $0.id == id }?.name }
    }
}

struct FleetScreen: View {
    let session: GameSession
    @State private var openID: Int?
    @State private var showPilots = FleetScreen.startOnPilots

    var body: some View {
        let world = session.world
        Page {
            // The Fleet sub-tab above already names the screen, so this row only counts and switches.
            HStack {
                let pilots = world.ops.pilots.count
                Text(showPilots ? "\(pilots) pilot\(pilots == 1 ? "" : "s")" : "\(world.aircraft.count) aircraft").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                Spacer()
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
            if world.aircraft.isEmpty { EmptyNote("You have no aircraft yet. Open the Hangar on the left to buy your first one.") }
            ForEach(world.aircraft) { plane in
                if let type = plane.type {
                    let status = FleetText.status(plane, in: world)
                    Button { openID = plane.id } label: {
                        HStack(alignment: .top, spacing: 12) {
                            AircraftSpriteView(family: type.family, branding: plane.livery?.branding ?? world.airline.branding, pixel: 2).frame(width: 130)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plane.registration).pixelFont(13.333).foregroundStyle(Theme.accent)
                                Text(type.displayName.uppercased()).pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(status.text).pixelFont(10.667).foregroundStyle(status.color)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Route: \(FleetText.routeName(plane, in: world))").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            StatBar(label: "Condition", value: plane.condition, color: plane.condition < 50 ? Theme.bad : Theme.good).frame(width: 170)
                        }
                        .padding(12)
                        .background(PixelPanel())
                    }
                    .buttonStyle(.tap)
                    .accessibilityHint("Opens the aircraft: routes, kits, checks and sale.")
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
                ScreenHeader(title: plane.registration) { Button { dismiss() } label: { HangarButtonText("Close") }.buttonStyle(.small) }
                HangarNotice(session: session)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Card {
                            HStack(alignment: .top, spacing: 14) {
                                AircraftSpriteView(family: type.family, branding: plane.livery?.branding ?? world.airline.branding, pixel: 3)
                                VStack(alignment: .leading, spacing: 4) {
                                    let status = FleetText.status(plane, in: world)
                                    Text(type.displayName.uppercased()).pixelFont(13.333).foregroundStyle(Theme.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(status.text).pixelFont(10.667).foregroundStyle(status.color)
                                        .fixedSize(horizontal: false, vertical: true)
                                    KeyValueRow("Seats", "\(type.seats)")
                                    KeyValueRow("Range", Format.km(Double(type.rangeKm)))
                                    KeyValueRow("Age", "\(Int(plane.ageYears(atDay: world.clock.dayIndex))) years")
                                    KeyValueRow("Flights", Format.number(plane.totalFlights))
                                    KeyValueRow("Worth", Format.dollars(world.saleValue(of: plane)))
                                }
                            }
                        }
                        SectionTitle("Upkeep")
                        UpkeepCard(session: session, plane: plane)
                        SectionTitle("Crew and kit")
                        KitsCard(session: session, aircraftID: aircraftID)
                        SectionTitle("Route")
                        if plane.routeID != nil { SharedRoutesCard(session: session, plane: plane) }
                        routePicker(plane: plane, type: type, world: world)
                        SectionTitle("Paint")
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(plane.livery == nil ? "Wearing the airline livery." : "Wearing the special livery \"\(Words.liveryName(plane.livery?.name ?? ""))\".").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                                HStack(spacing: 8) {
                                    Button { editingLivery = true } label: { HangarButtonText("Special livery") }.buttonStyle(.small)
                                    if plane.livery != nil {
                                        Button { session.perform { try $0.setLivery(aircraftID: aircraftID, livery: nil) } } label: { HangarButtonText("Use airline livery") }.buttonStyle(.small)
                                    }
                                }
                            }
                        }
                        SectionTitle("Sell")
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                if let reason = sellBlock(plane) {
                                    Text(reason).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                                }
                                Button { confirmSell = true } label: { HangarButtonText("Sell for \(Format.dollars(world.saleValue(of: plane)))") }
                                    .buttonStyle(.smallDanger)
                                    .disabled(sellBlock(plane) != nil)
                            }
                        }
                    }
                }
            } else {
                ScreenHeader(title: "Aircraft") { Button { dismiss() } label: { HangarButtonText("Close") }.buttonStyle(.small) }
                EmptyNote("This aircraft is gone.")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .screenBackground()
        .onAppear { session.notice = nil }
        .pixelConfirm("Sell this aircraft?", message: "The dealer pays less than it is worth.", confirm: "Sell", destructive: true, isPresented: $confirmSell) {
            if session.perform(sound: .coin, { _ = try $0.sell(aircraftID: aircraftID) }) { dismiss() }
        }
        .sheet(isPresented: $editingLivery) { LiverySheet(session: session, aircraftID: aircraftID) }
    }

    /// Why the aircraft cannot be sold right now, in the player's words, or nil when it can.
    private func sellBlock(_ plane: Aircraft) -> String? {
        if !plane.isDelivered { return "It can be sold once it has arrived." }
        if plane.routeID != nil { return "Take it off its route first, then it can be sold." }
        return nil
    }

    @ViewBuilder private func routePicker(plane: Aircraft, type: AircraftType, world: World) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                if world.routes.isEmpty {
                    Text("No routes yet. Plan one on the Map, then come back to assign this aircraft.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !plane.isDelivered {
                    Text("It can fly a route once it has arrived.").pixelFont(10.667).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
                } else if plane.awaitingRestoration {
                    Text("Restore it first (see Upkeep above). Then it can fly a route.").pixelFont(10.667).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(world.routes) { route in
                    let problem = world.fitProblem(type: type, route: route, kits: plane.kits)
                    let current = plane.routeID == route.id
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(route.name).pixelFont(13.333).foregroundStyle(current ? Theme.accent : Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let problem { Text(Messages.describe(problem)).pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true) }
                            else if !current { AssignOutlook(world: world, route: route, type: type) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if current {
                            Button { session.perform { try $0.unassign(aircraftID: aircraftID) } } label: { HangarButtonText("Take off route") }.buttonStyle(.small)
                        } else {
                            // Assigning moves the aircraft off every route it flies now, so the button says so when it has one.
                            Button { session.perform { try $0.assign(aircraftID: aircraftID, toRoute: route.id) } } label: { HangarButtonText(plane.routeID == nil ? "Assign" : "Move here") }
                                .buttonStyle(.smallProminent)
                                .disabled(problem != nil || !plane.isDelivered || plane.awaitingRestoration)
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
                        if session.perform({ try $0.setLivery(aircraftID: aircraftID, livery: SpecialLivery(name: name, branding: branding)) }) { dismiss() }
                    }.buttonStyle(.smallProminent)
                }
            }
            HangarNotice(session: session)
            PixelField(title: "Livery name", text: $name, prompt: "Retro")
            BrandingEditor(branding: $branding, airlineName: session.world.airline.name)
        }
        .padding(16)
        .screenBackground()
        .onAppear {
            if let plane = session.world.aircraft.first(where: { $0.id == aircraftID }) {
                branding = plane.livery?.branding ?? session.world.airline.branding
                name = Words.liveryName(plane.livery?.name ?? "Special")
            }
        }
    }
}
