// CoreWorld/FirstSession.swift: a new player's first session should pay. The airline's very first route starts fully known
// (people already know the new air service), so it earns from its first flight instead of building awareness for weeks.
// Every later route starts at Tuning.minimumMaturity and grows with flying, as before.
// The head start goes to the first route the airline's own aircraft can fly: a first route opened by mistake (a water strip for
// a wheeled Caravan, a leg out of range) does not use it up.

extension Tuning {
    /// Awareness of every leg of the airline's very first route (1.0 is fully known).
    public static let firstRouteMaturity = 1.0
}

extension World {
    /// True until the airline has a route that one of its aircraft can fly, or has flown any route. Once a route has flown it
    /// never comes back, even if every route is closed, so this happens once a game.
    public var opensFirstRoute: Bool {
        guard airline.stats.flights == 0 else { return false }
        return !routes.contains { fleetCanFly(route: $0) }
    }

    /// Whether at least one aircraft of the airline (with its kits) could fly this route. Seasons are not counted, as in fitProblem.
    public func fleetCanFly(route: Route) -> Bool {
        aircraft.contains { plane in
            guard let type = plane.type else { return false }
            return fitProblem(type: type, route: route, kits: plane.kits) == nil
        }
    }
}
