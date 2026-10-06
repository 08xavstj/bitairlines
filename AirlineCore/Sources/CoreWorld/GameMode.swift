// CoreWorld/GameMode.swift: how strict the world is. Chosen when the airline is founded; it never changes during a game.

public enum GameMode: String, Sendable, Hashable, Codable, CaseIterable {
    /// Any aircraft uses any land runway, no weather, no daylight limits, no frozen lakes, no slots.
    case easy
    /// The game as designed: runways, surfaces, weather, daylight on unlit strips, lakes that freeze.
    case normal
    /// Normal, plus fuel is only sold at real fuel stops, so long chains of small strips need tankering or a fuel depot.
    case realism
    /// Normal rules with money that never runs out and every certificate level open: for building and painting.
    case sandbox

    public var checksRunways: Bool { self != .easy }
    public var hasWeather: Bool { self != .easy }
    public var daylightLimits: Bool { self != .easy }
    public var lakesFreeze: Bool { self != .easy }
    public var fuelOnlyWhereSold: Bool { self == .realism }
    public var needsSlots: Bool { self == .normal || self == .realism }
    public var unlimitedMoney: Bool { self == .sandbox }
}
