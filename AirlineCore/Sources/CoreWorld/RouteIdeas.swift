// CoreWorld/RouteIdeas.swift: routes the game suggests, so the player does not have to guess. From each airport the airline already
// uses, it looks at nearby airports its own aircraft can reach, forecasts each pair for one aircraft and keeps the ones that pay, best first.
// Codes and numbers only; the app writes the words.
import CoreCatalog

/// Why a suggested route is worth a look. The app turns it into a sentence.
public enum RouteIdeaReason: String, Sendable, Hashable, Codable {
    /// `place` is a fly-in community with no road: people and freight have to fly.
    case noRoadTown
    /// Many people a day travel between the two airports.
    case bigMarket
    /// `place` is new to the network.
    case extendsNetwork
    /// Both airports are already on the network.
    case linksNetwork
}

/// What kind of routes to suggest.
public enum RouteIdeaFocus: String, Sendable, Hashable, Codable, CaseIterable {
    /// Routes around the network for the aircraft the airline has (the bush routes of the start).
    case smallStrips
    /// Routes to bigger towns and cities the airline may serve at its level, judged for its biggest aircraft and for bigger ones it could buy
    /// (see RouteIdeasBigger.swift).
    case biggerCities
}

/// One suggested route: two stops, the aircraft type it was judged for, and what one aircraft of that type should earn on it.
public struct RouteIdea: Sendable, Hashable, Identifiable {
    /// The airport the airline already uses first, then the other end.
    public var stops: [String]
    public var typeID: String
    /// Forecast profit per day with one aircraft, once people know the route.
    public var profitPerDay: Double
    public var passengersPerDay: Double
    public var distanceKm: Double
    public var reason: RouteIdeaReason
    /// The airport the reason is about.
    public var place: String
    /// False when the idea is judged for a type the airline does not have yet (one it could buy in the hangar).
    public var typeOwned: Bool = true

    public var id: String { stops.joined(separator: "-") }
}

/// How wide the search for route ideas looks. These shape the search only, not the game's balance.
public enum RouteIdeaSearch {
    /// Shortest leg worth suggesting, in km.
    public static let minKm = 50.0
    /// Longest leg suggested to a small airline (levels up to `smallAirlineLevel`), in km.
    public static let smallAirlineMaxKm = 800.0
    public static let smallAirlineLevel = 2
    /// How many of the nearest airports are looked at around each network airport.
    public static let nearestCount = 60
    /// How many network airports (home first) are searched from.
    public static let maxNetworkAirports = 40
    /// Isolation at or above which a town counts as having no road.
    public static let noRoadIsolation = 0.5
    /// Forecast passengers a day at or above which a route counts as a big market.
    public static let bigMarketPassengers = 30.0

    /// The same key for a pair in either direction.
    static func pairKey(_ a: String, _ b: String) -> String { a < b ? a + "|" + b : b + "|" + a }
}

extension World {
    /// Up to `limit` routes worth opening, best first: from an airport the airline uses to one nearby that one of its own aircraft
    /// types can fly, not already flown in either direction, open to the airline now, and forecast to make money with one aircraft.
    /// With `focus` `.biggerCities` the ideas lead to bigger towns and cities instead (see `biggerCityIdeas`).
    public func routeIdeas(limit: Int = 5, focus: RouteIdeaFocus = .smallStrips) -> [RouteIdea] {
        if focus == .biggerCities { return biggerCityIdeas(limit: limit) }
        let types = ideaTypes()
        guard limit > 0, !types.isEmpty else { return [] }
        let network = networkAirports
        let inNetwork = Set(network)
        var flown = Set<String>()
        for route in routes {
            for leg in route.legs { flown.insert(RouteIdeaSearch.pairKey(leg.from, leg.to)) }
        }
        let reach = Double(types.map(\.rangeKm).max() ?? 0)
        let maxKm = airline.level <= RouteIdeaSearch.smallAirlineLevel ? min(reach, RouteIdeaSearch.smallAirlineMaxKm) : reach

        var checked = Set<String>()
        var ideas: [RouteIdea] = []
        for code in network.prefix(RouteIdeaSearch.maxNetworkAirports) {
            guard let from = AirportCatalog.airport(code) else { continue }
            let near = AirportCatalog.nearest(latitude: from.latitude, longitude: from.longitude, limit: RouteIdeaSearch.nearestCount) { $0.code != code }
            for to in near {
                let km = from.distanceKm(to: to)
                guard km >= RouteIdeaSearch.minKm, km <= maxKm else { continue }
                let key = RouteIdeaSearch.pairKey(code, to.code)
                guard !flown.contains(key), !checked.contains(key) else { continue }
                checked.insert(key)
                let stops = [code, to.code]
                guard routeProblem(stops: stops) == nil else { continue }
                if let idea = bestIdea(stops: stops, km: km, types: types, inNetwork: inNetwork) { ideas.append(idea) }
            }
        }
        ideas.sort { a, b in a.profitPerDay != b.profitPerDay ? a.profitPerDay > b.profitPerDay : a.id < b.id }
        return Array(ideas.prefix(limit))
    }

    /// A parked aircraft of the idea's type that could fly it right away (nil if there is none): one already at a stop first, then the lowest id.
    public func idleAircraftID(for idea: RouteIdea) -> Int? {
        guard let type = AircraftCatalog.type(idea.typeID), let route = ideaRoute(stops: idea.stops) else { return nil }
        let free = aircraft.filter { plane in
            guard plane.typeID == idea.typeID, plane.routeID == nil, plane.jobID == nil, case .idle = plane.status else { return false }
            return fitProblem(type: type, route: route, kits: plane.kits) == nil
        }
        let ordered = free.sorted { $0.id < $1.id }
        let here = ordered.first { $0.location == idea.stops[0] } ?? ordered.first { idea.stops.contains($0.location) }
        return (here ?? ordered.first)?.id
    }

    /// The types ideas are judged for: the delivered fleet's types; if none, the types on order; if none, the cheapest the airline may buy.
    func ideaTypes() -> [AircraftType] {
        var ids = Set(aircraft.filter(\.isDelivered).map(\.typeID))
        if ids.isEmpty { ids = Set(aircraft.map(\.typeID)) }
        let owned = ids.sorted().compactMap { AircraftCatalog.type($0) }
        if !owned.isEmpty { return owned }
        let cheapest = AircraftCatalog.available(atLevel: airline.level).min { $0.priceUSD != $1.priceUSD ? $0.priceUSD < $1.priceUSD : $0.id < $1.id }
        return cheapest.map { [$0] } ?? []
    }

    /// A route through the stops as it would be on the day it opens, for forecasting only (nil if an airport is unknown).
    func ideaRoute(stops: [String]) -> Route? {
        guard let legs = makeLegs(stops: stops) else { return nil }
        return Route(id: 0, name: "", stops: stops, fareMultiplier: 1.0, carriesCargo: true, frequency: 1, autoFrequency: true, legs: legs, aircraftIDs: [],
                     openedDay: clock.dayIndex, flights: 0, revenueThisMonth: 0, costThisMonth: 0, revenueLastMonth: 0, costLastMonth: 0)
    }

    /// Whether the airline could fly this type on the route: as delivered, or as one of its own aircraft of the type with its kits.
    func canFlyIdea(type: AircraftType, route: Route) -> Bool {
        if fitProblem(type: type, route: route) == nil { return true }
        return aircraft.contains { $0.typeID == type.id && !$0.kits.isEmpty && fitProblem(type: type, route: route, kits: $0.kits) == nil }
    }

    /// The best paying of the types on one pair, as an idea (nil if none of them makes money there).
    func bestIdea(stops: [String], km: Double, types: [AircraftType], inNetwork: Set<String>) -> RouteIdea? {
        guard types.contains(where: { $0.canFly(km: km) }), let route = ideaRoute(stops: stops) else { return nil }
        var best: RouteForecast?
        for type in types where type.canFly(km: km) && canFlyIdea(type: type, route: route) {
            let f = forecast(on: route, type: type, frequency: nil, aircraftCount: 1)
            if f.isViable && f.profitPerDay > (best?.profitPerDay ?? 0) { best = f }
        }
        guard let best else { return nil }
        let (reason, place) = ideaReason(stops: stops, passengersPerDay: best.passengersPerDay, inNetwork: inNetwork)
        let owned = aircraft.contains { $0.typeID == best.typeID }
        return RouteIdea(stops: stops, typeID: best.typeID, profitPerDay: best.profitPerDay, passengersPerDay: best.passengersPerDay,
                         distanceKm: km, reason: reason, place: place, typeOwned: owned)
    }

    /// The main reason a pair is worth flying, and the airport it is about. The far end is looked at first.
    func ideaReason(stops: [String], passengersPerDay: Double, inNetwork: Set<String>) -> (RouteIdeaReason, String) {
        let far = stops[1]
        for code in [far, stops[0]] {
            if let airport = AirportCatalog.airport(code), Demand.isolation(airport) >= RouteIdeaSearch.noRoadIsolation { return (.noRoadTown, code) }
        }
        if passengersPerDay >= RouteIdeaSearch.bigMarketPassengers { return (.bigMarket, far) }
        if !inNetwork.contains(far) { return (.extendsNetwork, far) }
        return (.linksNetwork, far)
    }
}
