// CoreWorld/RouteIdeasBigger.swift: suggested routes for an airline growing out of the bush. Instead of the strips around the network,
// it looks at bigger towns and cities the airline may serve at its level: from its own bigger airports and from big ones near its network.
// Each pair is judged for the aircraft the airline has and for a few bigger types it could buy (new, or used in the hangar this week),
// so an idea can say "with a Twin Otter you could buy". From level 3 most of these cities hand out slots: each idea carries the
// slots it still needs and their price (SlotNeeds.swift), and ranks with that bill counted. Codes and numbers only; the app writes the words.
import CoreCatalog

extension RouteIdeaSearch {
    /// Longest leg suggested to a small airline when looking at bigger cities, in km: towns lie further apart than strips.
    public static let biggerCitiesSmallAirlineMaxKm = 1200.0
    /// How many big airports near the network (not on it yet) are searched from.
    public static let biggerCityNearOrigins = 4
    /// How many bigger types the airline could buy are judged, spread from the smallest to the biggest.
    public static let biggerBuyableTypes = 4
}

extension World {
    /// Up to `limit` routes to bigger towns and cities, best first. The far end has at least `Tuning.biggerCityPopulation(level:)` people,
    /// every stop is open to the airline now (level and permit), and the route is forecast to make money with one aircraft.
    public func biggerCityIdeas(limit: Int) -> [RouteIdea] {
        let types = biggerIdeaTypes()
        guard limit > 0, !types.isEmpty else { return [] }
        let threshold = Tuning.biggerCityPopulation(level: airline.level)
        let network = networkAirports
        let inNetwork = Set(network)
        var flown = Set<String>()
        for route in routes {
            for leg in route.legs { flown.insert(RouteIdeaSearch.pairKey(leg.from, leg.to)) }
        }
        let reach = Double(types.map(\.rangeKm).max() ?? 0)
        let maxKm = airline.level <= RouteIdeaSearch.smallAirlineLevel ? min(reach, RouteIdeaSearch.biggerCitiesSmallAirlineMaxKm) : reach

        var checked = Set<String>()
        var ideas: [RouteIdea] = []
        for code in biggerIdeaOrigins(threshold: threshold, network: network) {
            guard let from = AirportCatalog.airport(code) else { continue }
            let near = AirportCatalog.nearest(latitude: from.latitude, longitude: from.longitude, limit: RouteIdeaSearch.nearestCount) { airport in
                airport.code != code && isBiggerCity(airport, threshold: threshold)
            }
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
        ideas.sort(by: World.ideaOrder)
        return Array(ideas.prefix(limit))
    }

    /// A town big enough to count as a bigger city at this level, that the airline may fly to now.
    func isBiggerCity(_ airport: Airport, threshold: Int) -> Bool {
        airport.population >= threshold && Progression.requiredLevel(for: airport) <= airline.level && airline.permits.contains(airport.country)
    }

    /// Where bigger-city routes start: the network's own bigger airports (home first), then the big airports closest to the network.
    func biggerIdeaOrigins(threshold: Int, network: [String]) -> [String] {
        let minimum = Int(Double(threshold) * Tuning.biggerCityOriginShare)
        let searched = Array(network.prefix(RouteIdeaSearch.maxNetworkAirports))
        var origins = searched.filter { code in (AirportCatalog.airport(code)?.population ?? 0) >= minimum }
        let inNetwork = Set(network)
        var near: [(code: String, km: Double)] = []
        for code in searched {
            guard let from = AirportCatalog.airport(code) else { continue }
            let found = AirportCatalog.nearest(latitude: from.latitude, longitude: from.longitude, limit: RouteIdeaSearch.biggerCityNearOrigins) { airport in
                !inNetwork.contains(airport.code) && isBiggerCity(airport, threshold: threshold)
            }
            for to in found {
                let km = from.distanceKm(to: to)
                if let k = near.firstIndex(where: { $0.code == to.code }) { near[k].km = min(near[k].km, km) } else { near.append((code: to.code, km: km)) }
            }
        }
        near.sort { $0.km != $1.km ? $0.km < $1.km : $0.code < $1.code }
        for entry in near.prefix(RouteIdeaSearch.biggerCityNearOrigins) where !origins.contains(entry.code) { origins.append(entry.code) }
        return origins
    }

    /// The types bigger-city ideas are judged for: the fleet's types first, then a spread of types the airline could buy now
    /// (new, or used in the hangar this week) that are at least as big as its biggest and can be delivered (to the headquarters,
    /// or the nearest airport of the network they can use; FleetActions.swift).
    func biggerIdeaTypes() -> [AircraftType] {
        let ownedIDs = Set(aircraft.map(\.typeID))
        let owned = ownedIDs.sorted().compactMap { AircraftCatalog.type($0) }
        let biggest = owned.map(\.seats).max() ?? 0
        let listed = Set(market.listings.map(\.typeID))
        let buyable = AircraftCatalog.available(atLevel: airline.level).filter { type in
            !ownedIDs.contains(type.id) && (type.inProduction || listed.contains(type.id)) && type.seats >= biggest && deliveryProblem(type) == nil
        }
        let ordered = buyable.sorted { a, b in
            if a.seats != b.seats { return a.seats < b.seats }
            return a.priceUSD != b.priceUSD ? a.priceUSD < b.priceUSD : a.id < b.id
        }
        let n = RouteIdeaSearch.biggerBuyableTypes
        var picked: [AircraftType] = []
        if ordered.count <= n {
            picked = ordered
        } else {
            for k in 0..<n {
                let type = ordered[k * (ordered.count - 1) / (n - 1)]
                if !picked.contains(where: { $0.id == type.id }) { picked.append(type) }
            }
        }
        return owned + picked
    }
}
