import SwiftUI
import CoreCatalog
import CoreWorld

/// The words for the next step (Core gives a code and numbers, see AirlineCore NextStep.swift).
enum NextStepWords {
    static func line(_ step: NextStep, world: World) -> String {
        switch step {
        case .openFirstRoute:
            return "Open your first route"
        case .assignAircraft(let id):
            let registration = world.aircraft.first { $0.id == id }?.registration ?? "Your aircraft"
            return "Give \(registration) a route in Fleet"
        case .openSecondRoute:
            return "Open a second route"
        case .buyAircraft(let typeID, let price):
            return "\(typeName(typeID)) for sale at \(Format.compactMoney(price)) in the Hangar"
        case .saveForAircraft(let typeID, let price, let days):
            if let days { return "\(typeName(typeID)) affordable \(inDays(days))" }
            return "\(typeName(typeID)) costs \(Format.compactMoney(price))"
        case .buyLevel(let level, let fee):
            return "Level \(level) is ready: \(Format.compactMoney(fee)) under Money"
        case .saveForLevel(let level, let fee, let days):
            if let days { return "Level \(level) fee affordable \(inDays(days))" }
            return "Level \(level) needs \(Format.compactMoney(fee)) for the fee"
        case .levelNeedsReputation(let level, let reputation):
            return "Level \(level) needs reputation \(reputation)"
        case .levelNeedsRevenue(let level, let revenue, let days):
            let base = "Level \(level) needs \(Format.compactMoney(revenue)) more revenue"
            if let days, days > 0 { return base + ", about \(days) day\(days == 1 ? "" : "s")" }
            return base
        case .topLevel:
            return "Top certificate held"
        }
    }

    static func typeName(_ id: String) -> String { AircraftCatalog.type(id)?.name ?? id }

    static func inDays(_ days: Int) -> String {
        days <= 0 ? "now" : "in \(days) day\(days == 1 ? "" : "s")"
    }
}

/// Keeps the next step between clock ticks: it is worked out again only when something it depends on changes
/// (a new day, the network, the fleet, the market, the level, or the bank balance moving by a noticeable amount).
final class NextStepCache {
    struct Key: Hashable {
        var day: Int
        var routes: [Int]
        var aircraft: [Int]
        var parked: Int
        var listings: Int
        var level: Int
        var reputation: Int
        var cashStep: Int
        var revenueStep: Int
    }

    private var key: Key?
    private var step: NextStep = .openFirstRoute

    func step(for world: World) -> NextStep {
        let parked = world.aircraft.filter { plane in
            if case .idle = plane.status { return plane.routeID == nil } else { return false }
        }.count
        let now = Key(day: world.clock.dayIndex, routes: world.routes.map(\.id), aircraft: world.aircraft.map(\.id), parked: parked,
                      listings: world.market.nextListingID, level: world.airline.level, reputation: Int(world.airline.reputation),
                      cashStep: world.airline.cash / 25_000, revenueStep: world.airline.stats.revenue / 50_000)
        if now != key {
            key = now
            step = world.nextStep
        }
        return step
    }
}

/// One short line on the map toolbar: the next thing worth doing.
struct NextStepLine: View {
    let session: GameSession
    @State private var cache = NextStepCache()

    var body: some View {
        let world = session.world
        let text = NextStepWords.line(cache.step(for: world), world: world)
        HStack(spacing: 6) {
            Text("NEXT").pixelFont(8).foregroundStyle(Theme.onAccent).padding(.horizontal, 4).padding(.vertical, 2).background(Theme.accent)
            Text(text).pixelFont(10.667).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8).frame(minHeight: 36)
        .background(PixelShape(step: 2).fill(Theme.surface.opacity(0.92)))
        .overlay(PixelShape(step: 2).inset(by: 1).stroke(Theme.panelBorder, lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next: \(text)")
    }
}
