import SwiftUI
import CoreCatalog
import CoreWorld

/// In the aircraft sheet: the routes this aircraft can be put on. Its own route first, then the routes it can fly (with the empty
/// flight it needs to get there), then, greyed and without a button, the routes it cannot fly and why.
struct AircraftRoutePicker: View {
    let session: GameSession
    let plane: Aircraft
    let type: AircraftType

    var body: some View {
        let world = session.world
        let current = world.routes.filter { $0.id == plane.routeID }
        let others = world.routes.filter { $0.id != plane.routeID }
        let cache = PlaneChoiceCache.shared
        let rows = others.map { route -> RouteOption in
            let choice = cache.choice(world: world, aircraftID: plane.id, routeID: route.id)
            return RouteOption(route: route, problem: choice == nil ? .unknownAircraft(plane.id) : choice?.problem)
        }
        let open = rows.filter { $0.problem == nil }.map(\.route)
        let blocked = rows.filter { $0.problem != nil }
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
                ForEach(current) { route in
                    HStack(alignment: .top, spacing: 12) {
                        Text(route.name).pixelFont(13.333).foregroundStyle(Theme.accent)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        Button { session.perform { try $0.unassign(aircraftID: plane.id) } } label: { HangarButtonText("Take off route") }.buttonStyle(.small)
                    }
                }
                ForEach(open) { route in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(route.name).pixelFont(13.333).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                            AssignOutlook(world: world, route: route, type: type)
                            Text(PlaneChoiceWords.routePlan(cache.choice(world: world, aircraftID: plane.id, routeID: route.id)?.ferry))
                                .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Assigning moves the aircraft off every route it flies now, so the button says so when it has one.
                        Button { session.perform { try $0.assign(aircraftID: plane.id, toRoute: route.id) } } label: { HangarButtonText(plane.routeID == nil ? "Assign" : "Move here") }
                            .buttonStyle(.smallProminent)
                    }
                }
                if !blocked.isEmpty && (!open.isEmpty || !current.isEmpty) {
                    Text("It cannot fly these:").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                }
                ForEach(blocked) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.route.name).pixelFont(13.333).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        if let problem = row.problem {
                            Text(PlaneChoiceWords.routeReason(problem, route: row.route, plane: plane, in: world).capitalizedFirst)
                                .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(0.6)
                }
            }
        }
    }
}

/// A route and why an aircraft cannot join it (nil if it can).
struct RouteOption: Identifiable {
    let route: Route
    let problem: WorldError?
    var id: Int { route.id }
}

extension String {
    /// The same text with its first letter in capitals ("too far" -> "Too far").
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
