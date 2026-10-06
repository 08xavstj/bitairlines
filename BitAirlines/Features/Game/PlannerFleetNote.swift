import SwiftUI
import CoreCatalog
import CoreWorld

/// In the route planner: whether an aircraft the player owns can fly the route being planned. If one stretch is too long for all
/// of them, it says which (the map draws it in red) and offers a stop in between that makes it flyable.
struct PlannerFleetNote: View {
    let world: World
    @Binding var stops: [String]
    let check: PlannerCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !check.hasAircraft {
                Text("You have no aircraft yet. The list below shows what would fly it.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if check.fits {
                Text("Your aircraft that can fly it: " + registrations.joined(separator: ", ")).pixelFont(10.667).foregroundStyle(Theme.good)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let l = check.blockedLeg, l < stops.count {
                let from = stops[l]
                let to = stops[(l + 1) % stops.count]
                Text("None of your aircraft can fly \(Place.name(from)) to \(Place.name(to)): " + reason + ".")
                    .pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
                if let stop = check.suggestedStop {
                    Text("A stop at \(Place.name(stop)) on the way makes it flyable.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Add a stop at \(Place.name(stop))") { addStop(stop, after: l) }.buttonStyle(.small)
                } else {
                    Text("You can still open it and buy an aircraft that flies it.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let problem = check.fleetProblem {
                Text("No one aircraft of yours can fly the whole route: " + PlaneChoiceWords.reason(problem) + ".")
                    .pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
            }
            // A new airline has one aircraft and little cash: its first route should be one that aircraft can fly today.
            if world.routes.isEmpty && check.hasAircraft && !check.fits {
                Text("For your first route, pick one your own aircraft can fly, so it starts earning at once.")
                    .pixelFont(10.667).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var registrations: [String] {
        check.fittingAircraftIDs.compactMap { id in world.aircraft.first { $0.id == id }?.registration }
    }

    private var reason: String {
        guard let problem = check.blockedProblem else { return "too far" }
        return PlaneChoiceWords.reason(problem)
    }

    /// Puts the stop between stops[l] and the next one (at the end when the stretch is the one back to the start).
    private func addStop(_ code: String, after l: Int) {
        guard !stops.contains(code), stops.count < World.maxStops else { return }
        stops.insert(code, at: min(l + 1, stops.count))
    }
}
