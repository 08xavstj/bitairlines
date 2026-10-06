import SwiftUI
import CoreCatalog
import CoreWorld

/// The next heavy check (when and what it costs), or the restoration a barn find needs before it can fly.
struct UpkeepCard: View {
    let session: GameSession
    let plane: Aircraft

    var body: some View {
        let world = session.world
        Card {
            VStack(alignment: .leading, spacing: 8) {
                if plane.awaitingRestoration {
                    let cost = world.restorationCost(aircraftID: plane.id) ?? 0
                    let days = world.restorationDays(aircraftID: plane.id) ?? 0
                    Text("Barn find. It cannot fly until it is restored: about \(Format.compactMoney(cost)) and \(days) days in the hangar. It comes out near new, in the heritage livery.")
                        .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    let problem = world.restorationProblem(aircraftID: plane.id)
                    if let problem {
                        Text(Messages.describe(problem, cash: world.airline.cash)).pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
                    }
                    Button { session.perform(sound: .coin) { try $0.startRestoration(aircraftID: plane.id) } } label: { HangarButtonText("Restore for \(Format.compactMoney(cost))") }
                        .buttonStyle(.smallProminent)
                        .disabled(problem != nil)
                } else {
                    Text(heavyCheckLine(world)).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
                // In the hangar (a check, a repair or a restoration): the optional ad that finishes the work now.
                RewardButton(session: session, kind: .instantCheck, target: plane.id)
            }
        }
    }

    /// "Heavy check due in about 14 months, about $110k and 14 days in the hangar."
    private func heavyCheckLine(_ world: World) -> String {
        let days = world.daysUntilHeavyCheck(plane)
        let months = Int((Double(days) / 30.4).rounded())
        let when: String
        if days <= 0 {
            when = "due now"
        } else if months < 1 {
            when = "due within a month"
        } else {
            when = "due in about \(months) month\(months == 1 ? "" : "s")"
        }
        return "Heavy check \(when), about \(Format.compactMoney(world.heavyCheckCost(plane))) and \(world.heavyCheckDays(plane)) days in the hangar."
    }
}

/// One aircraft on more than one route: what it flies, and the routes it could also fly.
struct SharedRoutesCard: View {
    let session: GameSession
    let plane: Aircraft

    var body: some View {
        let world = session.world
        let others = plane.otherRouteIDs.compactMap { id in world.routes.first { $0.id == id } }
        // Routes that meet its own: those it can also fly first, then (greyed, no button) those it cannot, with the reason.
        let options = world.routesToShare(aircraftID: plane.id).map { RouteOption(route: $0, problem: world.addRouteProblem(aircraftID: plane.id, routeID: $0.id)) }
        let candidates = options.filter { $0.problem == nil }
        let blocked = options.filter { $0.problem != nil }
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Flies: \(FleetText.routeNames(plane, in: world).joined(separator: ", "))").pixelFont(13.333).foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Sharing an aircraft fills the days its first route leaves it on the ground.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(others) { route in
                    HStack(alignment: .top, spacing: 12) {
                        Text(route.name).pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        Button { session.perform { try $0.removeRoute(aircraftID: plane.id, routeID: route.id) } } label: { HangarButtonText("Stop flying this one") }.buttonStyle(.small)
                    }
                }
                if !candidates.isEmpty && plane.allRouteIDs.count < World.maxRoutesPerAircraft {
                    Text("It could also fly:").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                    ForEach(candidates) { option in
                        HStack(alignment: .top, spacing: 12) {
                            Text(option.route.name).pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                            Button { session.perform { try $0.addRoute(aircraftID: plane.id, routeID: option.route.id) } } label: { HangarButtonText("Also fly") }.buttonStyle(.smallProminent)
                        }
                    }
                }
                if !blocked.isEmpty && plane.allRouteIDs.count < World.maxRoutesPerAircraft {
                    ForEach(blocked) { option in
                        Text(option.route.name + ": cannot share it, " + PlaneChoiceWords.reason(option.problem ?? .invalidChoice))
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).opacity(0.6)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}
