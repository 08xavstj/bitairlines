// CoreWorld/FirstSession.swift: a new player's first session should pay. The airline's very first route starts fully known
// (people already know the new air service), so it earns from its first flight instead of building awareness for weeks.
// Every later route starts at Tuning.minimumMaturity and grows with flying, as before.

extension Tuning {
    /// Awareness of every leg of the airline's very first route (1.0 is fully known).
    public static let firstRouteMaturity = 1.0
}

extension World {
    /// True until the airline opens its first route. A route opened and then closed still counts, so this happens once a game.
    public var opensFirstRoute: Bool { nextRouteID == 1 }
}
