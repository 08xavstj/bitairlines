import SwiftUI
import CoreWorld

/// On a route with more aircraft than it needs: moves the extra ones to the routes where they earn most. The route keeps the
/// ones it needs, so it is flown as before.
struct SpareAircraftButton: View {
    let session: GameSession
    let route: Route

    var body: some View {
        let spare = session.world.spareAircraft(routeID: route.id)
        if !spare.isEmpty {
            Button(spare.count == 1 ? "Move the spare aircraft" : "Move the \(spare.count) spare aircraft") { move() }
                .buttonStyle(.small)
                .accessibilityHint("Moves aircraft this route does not need to the routes where they earn most. This route keeps enough.")
        }
    }

    private func move() {
        var moves: [SpareMove] = []
        guard session.perform(sound: .coin, { moves = try $0.moveSpareAircraft(routeID: route.id) }) else { return }
        let world = session.world
        if moves.isEmpty {
            session.notice = "No other route earns more with another aircraft yet. Open a new route, or hire a fleet planner to keep checking each Monday."
            return
        }
        let lines = moves.map { move -> String in
            let reg = world.aircraft.first { $0.id == move.aircraftID }?.registration ?? "An aircraft"
            let to = world.routes.first { $0.id == move.toRouteID }.map { Place.list($0.stops, separator: " - ") } ?? "another route"
            return "\(reg) to \(to)"
        }
        session.notice = "Moved " + lines.joined(separator: ", ") + "."
    }
}
