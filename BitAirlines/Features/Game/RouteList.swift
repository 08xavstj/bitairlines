import SwiftUI
import CoreCatalog
import CoreWorld

/// What a route needs from the player, worst first. The routes list sorts and labels by it.
enum RouteAttention: Int, Comparable {
    case noAircraft, losingMoney, needsAircraft, spareAircraft, onJob, fine

    static func < (a: RouteAttention, b: RouteAttention) -> Bool { a.rawValue < b.rawValue }

    static func of(_ route: Route, in world: World) -> RouteAttention {
        if route.aircraftIDs.isEmpty {
            // Its aircraft is away on a job and comes back by itself afterwards (JobFlights.swift): nothing to do.
            return world.aircraftAwayOnJobs(routeID: route.id).isEmpty ? .noAircraft : .onJob
        }
        let week = route.last7Days
        if week.flights > 0 && week.profit < 0 { return .losingMoney }
        // Short only when the schedule asks for more flying than its aircraft can do (shared ones count as their share).
        if world.isShortOfAircraft(routeID: route.id) { return .needsAircraft }
        if !world.spareAircraft(routeID: route.id).isEmpty { return .spareAircraft }
        return .fine
    }

    /// Every route's attention, worked out once per redraw of the Routes screen (the summary, the order and the rows share it).
    static func table(_ world: World) -> [Int: RouteAttention] {
        var table: [Int: RouteAttention] = [:]
        for route in world.routes { table[route.id] = of(route, in: world) }
        return table
    }

    /// Whether the routes summary counts it as one to look at. An aircraft away on a job is not.
    var wantsALook: Bool { self != .fine && self != .onJob }

    var label: String? {
        switch self {
        case .noAircraft: "No aircraft"
        case .losingMoney: "Losing money"
        case .needsAircraft: "Needs an aircraft"
        case .spareAircraft: "Spare aircraft"
        case .onJob: "Aircraft on a job"
        case .fine: nil
        }
    }

    var color: Color {
        switch self {
        case .noAircraft, .losingMoney: Theme.bad
        case .needsAircraft, .spareAircraft: Theme.gold
        case .onJob: Theme.info
        case .fine: Theme.good
        }
    }
}

/// How the routes list is ordered.
enum RouteSort: Int {
    case attention, profit, name

    /// `attention` is `RouteAttention.table(world)` when the caller has it already.
    func sorted(_ routes: [Route], in world: World, attention: [Int: RouteAttention]? = nil) -> [Route] {
        switch self {
        case .attention:
            let keyed = routes.map { (route: $0, attention: attention?[$0.id] ?? RouteAttention.of($0, in: world), profit: RouteList.profitPerDay($0)) }
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
    /// `RouteAttention.table(world)` when the screen has it already.
    var table: [Int: RouteAttention]? = nil

    var body: some View {
        let total = world.routes.reduce(0) { $0 + RouteList.profitPerDay($1) }
        let attention = world.routes.filter { (table?[$0.id] ?? RouteAttention.of($0, in: world)).wantsALook }.count
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
    /// From `RouteAttention.table(world)` when the screen has it already.
    var known: RouteAttention? = nil
    let onOpen: () -> Void

    var body: some View {
        let attention = known ?? RouteAttention.of(route, in: world)
        let perDay = RouteList.profitPerDay(route)
        let hasFlown = route.last7Days.flights > 0 || route.last7Days.cost > 0
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.name).pixelFont(13.333).foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Text(attention == .onJob ? "Aircraft away on a job, \(RouteSteps.frequencyText(route.frequency))"
                         : "\(route.aircraftIDs.count) aircraft, \(RouteSteps.frequencyText(route.frequency))")
                        .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
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
