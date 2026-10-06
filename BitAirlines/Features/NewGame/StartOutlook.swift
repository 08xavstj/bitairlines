import Foundation
import CoreCatalog
import CoreWorld

/// What a start would earn, worked out before the airline is founded: a scratch world is made with World.newGame and asked for
/// the best first route from home for one starter aircraft (the same route the guide then suggests), plus how many airports
/// nearby the new airline may fly to.
struct StartOutlook: Equatable, Sendable {
    /// The far end of the best first route from home; nil when no route from home pays with this aircraft.
    var destination: String?
    var perDay: Double
    /// Airports within 600 km the new airline may open a route to (its level and permits allow it; the aircraft is not checked).
    var openNearby: Int
}

/// Keeps the outlooks per home, aircraft and rules, so each is worked out once. The work runs away from the main thread.
@MainActor
enum StartOutlooks {
    private static var cache: [String: StartOutlook] = [:]

    private static func key(_ home: String, _ typeID: String, _ mode: GameMode) -> String { "\(home)|\(typeID)|\(mode.rawValue)" }

    static func cached(home: String, typeID: String, mode: GameMode) -> StartOutlook? { cache[key(home, typeID, mode)] }

    /// The outlook for one start (nil if that start cannot be founded, for example an aircraft the budget does not cover).
    static func load(home: String, typeID: String, difficulty: Difficulty, mode: GameMode) async -> StartOutlook? {
        let k = key(home, typeID, mode)
        if let hit = cache[k] { return hit }
        let found = await Task.detached(priority: .userInitiated) {
            StartOutlooks.work(home: home, typeID: typeID, difficulty: difficulty, mode: mode)
        }.value
        if let found { cache[k] = found }
        return found
    }

    /// The aircraft a new airline starts with by default at this home: the Caravan when it is offered, else the first offer.
    static func defaultStarter(home: String, difficulty: Difficulty, mode: GameMode) -> String? {
        let offers = World.starterOffers(home: home, difficulty: difficulty, mode: mode)
        return (offers.first { $0.typeID == "c208" } ?? offers.first)?.typeID
    }

    nonisolated static func work(home: String, typeID: String, difficulty: Difficulty, mode: GameMode) -> StartOutlook? {
        let config = NewGameConfig(airlineName: "Preview Air", airlineCode: "PV", homeAirport: home, branding: .starter, difficulty: difficulty,
                                   starterTypeID: typeID, seed: 1, mode: mode)
        guard let world = try? World.newGame(config), let airport = AirportCatalog.airport(home) else { return nil }
        let idea = world.routeIdeas(limit: 20).first { $0.stops.first == home && $0.stops.count == 2 }
        let nearby = AirportCatalog.all.filter { other in
            other.code != home && other.distanceKm(to: airport) <= 600 && world.routeProblem(stops: [home, other.code]) == nil
        }.count
        return StartOutlook(destination: idea.map { $0.stops[1] }, perDay: idea?.profitPerDay ?? 0, openNearby: nearby)
    }
}

/// The words for an outlook.
enum StartOutlookWords {
    /// "Best first route: Inuvik to Mayo, about +$2.6K a day once people know it." or the gold warning when nothing pays.
    /// With `typeName` it says which aircraft it was judged for ("Best first route with the 208B Grand Caravan EX: ...").
    static func line(home: String, outlook: StartOutlook, typeName: String? = nil) -> String {
        let with = typeName.map { " with the \($0)" } ?? ""
        guard let destination = outlook.destination else {
            return "No first route from here pays" + (with.isEmpty ? " with this aircraft." : with + ".")
        }
        return "Best first route\(with): \(Place.name(home)) to \(Place.name(destination)), about \(Format.perDay(outlook.perDay)) once people know it."
    }

    /// Head office is paid every day on top of what routes earn.
    static var headOffice: String {
        "Head office costs \(Format.dollars(Int(Tuning.headOfficePerDay(level: 1)))) a day on top, so a first route should earn well above that."
    }
}
