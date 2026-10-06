import SwiftUI
import CoreCatalog
import CoreWorld

/// Choosing an aircraft for a route. The aircraft that can fly it come first, each with the empty flight it needs to get there;
/// the others are greyed underneath with the reason and cannot be picked.
struct RouteAssignSheet: View {
    let session: GameSession
    let routeID: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let world = session.world
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(title: "Add an aircraft") { Button("Close") { dismiss() }.buttonStyle(.small) }
            if let route = world.routes.first(where: { $0.id == routeID }) {
                let choices = PlaneChoiceCache.shared.routeChoices(world: world, routeID: routeID).filter { !route.aircraftIDs.contains($0.aircraftID) }
                let planes = PlaneChoiceWords.planesByID(world)
                Text(route.name).pixelFont(13.333).foregroundStyle(Theme.accent).fixedSize(horizontal: false, vertical: true)
                if world.aircraft.isEmpty {
                    EmptyNote("You have no aircraft yet. Buy one in the Hangar, then come back.")
                } else if choices.isEmpty {
                    EmptyNote("All your aircraft already fly this route.")
                } else if !choices.contains(where: \.canDo) {
                    EmptyNote("None of your other aircraft can fly this route now. Each one says why.")
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(choices) { choice in
                            if let plane = planes[choice.aircraftID] {
                                RoutePlaneRow(world: world, route: route, plane: plane, choice: choice) {
                                    if session.perform({ try $0.assign(aircraftID: plane.id, toRoute: routeID) }) { dismiss() }
                                }
                            }
                        }
                    }
                }
            } else {
                EmptyNote("That route is gone.")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .screenBackground()
    }
}

/// One aircraft in the route sheet: how it gets to the route, or (greyed) why it cannot fly it.
struct RoutePlaneRow: View {
    let world: World
    let route: Route
    let plane: Aircraft
    let choice: PlaneChoice
    let onAssign: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(plane.registration)  \(plane.type?.name ?? "")")
                    .pixelFont(13.333).foregroundStyle(choice.canDo ? Theme.textPrimary : Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                if let problem = choice.problem {
                    Text("Cannot fly it: " + PlaneChoiceWords.routeReason(problem, route: route, plane: plane, in: world))
                        .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(PlaneChoiceWords.routePlan(choice.ferry)).pixelFont(10.667).foregroundStyle(Theme.good).fixedSize(horizontal: false, vertical: true)
                    if let type = plane.type { AssignOutlookLine(world: world, route: route, type: type) }
                    if plane.routeID != nil {
                        Text("Leaves \(FleetText.routeName(plane, in: world)).").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if choice.canDo {
                Button(plane.routeID == nil ? "Assign" : "Move here") { onAssign() }.buttonStyle(.smallProminent)
            }
        }
        .padding(12)
        .background(PixelPanel())
        .opacity(choice.canDo ? 1 : 0.6)
    }
}
