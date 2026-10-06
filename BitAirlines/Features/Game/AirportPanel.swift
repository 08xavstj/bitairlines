import SwiftUI
import CoreCatalog
import CoreWorld

/// Facts about the airport the player tapped.
/// The buttons sit at the top and the facts scroll below them when the map is short (a small phone, the guide strip, a large
/// text size), so Plan a route and Build here are never pushed off the screen. The route planner panel works the same way.
struct AirportPanel: View {
    let world: World
    let airport: Airport
    let onPlan: () -> Void
    let onBuild: () -> Void
    let onClose: () -> Void
    /// For the Leave button (GrowthSheets.swift); nil hides it.
    var session: GameSession? = nil

    var body: some View {
        let locked = Progression.requiredLevel(for: airport) > world.airline.level && airport.code != world.airline.home
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(airport.label.uppercased()).pixelFont(13.333).foregroundStyle(Theme.accent).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    PixelSquareButton(icon: .close, label: "Close", action: onClose)
                }
                // Side by side when they fit, one above the other at the largest text sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { actions(locked: locked) }
                    VStack(alignment: .leading, spacing: 6) { actions(locked: locked) }
                }
                ViewThatFits(in: .vertical) {
                    facts
                    ScrollView { facts }
                }
            }
        }
        .frame(width: 340)
    }

    @ViewBuilder private func actions(locked: Bool) -> some View {
        Button("Plan a route") { onPlan() }.buttonStyle(.smallProminent).disabled(locked)
        Button("Build here") { onBuild() }.buttonStyle(.small).disabled(locked)
    }

    @ViewBuilder private var facts: some View {
        let required = Progression.requiredLevel(for: airport)
        let locked = required > world.airline.level && airport.code != world.airline.home
        let home = AirportCatalog.airport(world.airline.home)
        VStack(alignment: .leading, spacing: 6) {
            Text(airport.name).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            KeyValueRow("Country", CountryCatalog.country(airport.country)?.name ?? airport.country)
            KeyValueRow("People nearby", Format.people(airport.population))
            KeyValueRow("Runway", "\(Format.number(world.runwayFt(at: airport))) ft \(surfaceWord)")
            if airport.surface != .water && !world.isLit(airport) && world.ops.mode.daylightLimits { KeyValueRow("Lights", "None: daylight only", color: Theme.gold) }
            if world.ops.mode.fuelOnlyWhereSold { KeyValueRow("Fuel", world.sellsFuel(airport) ? "Sold here" : "None", color: world.sellsFuel(airport) ? Theme.good : Theme.gold) }
            if world.isFrozen(airport, month: world.clock.date.month) { KeyValueRow("Lake", "Frozen: skis only", color: Theme.info) }
            if world.needsSlots(airport) { KeyValueRow("Slots", "\(world.slotsHeld(at: airport.code)) held, \(world.slotsScheduled(at: airport.code)) used") }
            if let base = world.ops.bases.first(where: { $0.airport == airport.code }) {
                Text("Your base: " + base.facilities.map { Words.name($0) }.joined(separator: ", ")).pixelFont(10.667).foregroundStyle(Theme.good).fixedSize(horizontal: false, vertical: true)
            }
            if let home, home.code != airport.code { KeyValueRow("From home", Format.km(home.distanceKm(to: airport))) }
            HStack(spacing: 6) {
                Tag(text: "Level \(required)", color: locked ? Theme.bad : Theme.good)
                if !world.airline.permits.contains(airport.country) { Tag(text: "Permit needed", color: Theme.gold) }
            }
            if let session, world.leaveAirportProblem(code: airport.code) == nil { LeaveAirportButton(session: session, code: airport.code) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var surfaceWord: String {
        switch world.surface(at: airport) {
        case .gravel: return "gravel"
        case .water: return "water"
        case .paved: return "paved"
        }
    }
}
