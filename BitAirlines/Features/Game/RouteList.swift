import SwiftUI
import CoreCatalog
import CoreWorld

/// What a route needs from the player, worst first. The routes list sorts and labels by it.
enum RouteAttention: Int, Comparable {
    case noAircraft, losingMoney, needsAircraft, spareAircraft, fine

    static func < (a: RouteAttention, b: RouteAttention) -> Bool { a.rawValue < b.rawValue }

    static func of(_ route: Route, in world: World) -> RouteAttention {
        if route.aircraftIDs.isEmpty { return .noAircraft }
        let week = route.last7Days
        if week.flights > 0 && week.profit < 0 { return .losingMoney }
        if let needed = world.aircraftNeeded(routeID: route.id) {
            if route.aircraftIDs.count < needed { return .needsAircraft }
            if !world.spareAircraft(routeID: route.id).isEmpty { return .spareAircraft }
        }
        return .fine
    }

    var label: String? {
        switch self {
        case .noAircraft: "No aircraft"
        case .losingMoney: "Losing money"
        case .needsAircraft: "Needs an aircraft"
        case .spareAircraft: "Spare aircraft"
        case .fine: nil
        }
    }

    var color: Color {
        switch self {
        case .noAircraft, .losingMoney: Theme.bad
        case .needsAircraft, .spareAircraft: Theme.gold
        case .fine: Theme.good
        }
    }
}

/// How the routes list is ordered.
enum RouteSort: Int {
    case attention, profit, name

    func sorted(_ routes: [Route], in world: World) -> [Route] {
        switch self {
        case .attention:
            let keyed = routes.map { (route: $0, attention: RouteAttention.of($0, in: world), profit: RouteList.profitPerDay($0)) }
            return keyed.sorted { a, b in
                if a.attention != b.attention { return a.attention < b.attention }
                if a.profit != b.profit { return a.profit < b.profit }
                return a.route.id < b.route.id
            }.map(\.route)
        case .profit:
            return routes.sorted { a, b in
                let pa = RouteList.profitPerDay(a), pb = RouteList.profitPerDay(b)
                return pa != pb ? pa > pb : a.id < b.id
            }
        case .name:
            return routes.sorted { $0.name < $1.name }
        }
    }
}

enum RouteList {
    /// Average profit a day over the last 7 days (or since opening, if sooner).
    static func profitPerDay(_ route: Route) -> Int {
        route.last7Days.profit / max(1, min(Route.bookDays, route.book.recentDays))
    }
}

/// The line over the list: what all routes made, and how many want a look.
struct RoutesSummary: View {
    let world: World

    var body: some View {
        let total = world.routes.reduce(0) { $0 + RouteList.profitPerDay($1) }
        let attention = world.routes.filter { RouteAttention.of($0, in: world) != .fine }.count
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("All routes, last 7 days").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                    Text("\(Format.signedMoney(total)) a day").pixelFont(16).foregroundStyle(total >= 0 ? Theme.good : Theme.bad)
                }
                Spacer(minLength: 8)
                Text(attention == 0 ? "All running well" : "\(attention) to look at")
                    .pixelFont(10.667).foregroundStyle(attention == 0 ? Theme.good : Theme.gold)
                    .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One short row per route. Tapping it opens everything about the route.
struct RouteRow: View {
    let world: World
    let route: Route
    let onOpen: () -> Void

    var body: some View {
        let attention = RouteAttention.of(route, in: world)
        let perDay = RouteList.profitPerDay(route)
        let hasFlown = route.last7Days.flights > 0 || route.last7Days.cost > 0
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.name).pixelFont(13.333).foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Text("\(route.aircraftIDs.count) aircraft, \(RouteSteps.frequencyText(route.frequency))")
                        .pixelFont(10.667).foregroundStyle(Theme.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(hasFlown ? "\(Format.signedMoney(perDay)) a day" : "Not flown yet")
                        .pixelFont(13.333).foregroundStyle(hasFlown ? (perDay >= 0 ? Theme.good : Theme.bad) : Theme.textMuted)
                        .lineLimit(1).fixedSize()
                    if let label = attention.label { Tag(text: label, color: attention.color) }
                }
                PixelIconView(icon: .next, pixel: 2).foregroundStyle(Theme.accent).accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(PixelPanel())
        }
        .buttonStyle(.tap)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the schedule, fare and aircraft for this route.")
    }
}
