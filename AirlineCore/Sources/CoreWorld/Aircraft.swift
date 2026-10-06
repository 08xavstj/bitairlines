// CoreWorld/Aircraft.swift: one aircraft in the airline's fleet (live state; the model's fixed specs are in CoreCatalog.AircraftType).
import CoreCatalog

public enum Ownership: Sendable, Hashable, Codable {
    case owned
    /// Leased: pays `monthlyUSD` on the first of each month until `endDay` (a day index).
    case leased(monthlyUSD: Int, endDay: Int)
}

public enum AircraftStatus: Sendable, Hashable, Codable {
    /// Parked with nothing to do (no route, or just delivered).
    case idle
    /// On the ground between flights until the given minute.
    case boarding(until: Int)
    /// Airborne until the given minute.
    case flying(until: Int)
    case maintenance(until: Int)
    /// Out of service until the player resolves the issue with this id.
    case grounded(issue: Int)
    /// Bought but not yet delivered.
    case onOrder(until: Int)
}

/// The flight in progress: what was loaded, and what it will earn and cost when it lands.
public struct Flight: Sendable, Hashable, Codable {
    public var from: String
    public var to: String
    public var departedMinute: Int
    public var distanceKm: Double
    public var passengers: Int
    public var cargoKg: Int
    public var revenue: Int
    public var cost: Int
    /// A repositioning flight carries nothing and earns nothing.
    public var isFerry: Bool
}

public struct Aircraft: Sendable, Hashable, Codable, Identifiable {
    public var id: Int
    public var typeID: String
    public var registration: String
    /// Day index the aircraft was built (negative for aircraft older than the game).
    public var builtDay: Int
    /// 0...100. Falls with flying; scheduled maintenance restores it.
    public var condition: Double
    public var ownership: Ownership
    public var purchasePrice: Int
    /// The airport it is at, or last left from while flying.
    public var location: String
    public var status: AircraftStatus
    public var routeID: Int?
    /// Which leg of its route it flies next.
    public var legIndex: Int
    public var flight: Flight?
    /// A one-off paint scheme; without one the aircraft wears the airline's branding.
    public var livery: SpecialLivery?
    public var blockMinutesToday: Int
    public var totalFlights: Int
    public var totalBlockMinutes: Int
    /// Kits fitted (see Kits.swift); missing from older saves.
    var kitsStore: [Kit]?
    /// The job it is flying, if any (see JobFlights.swift).
    public var jobID: Int?
    /// The route it goes back to after the job.
    public var returnRouteID: Int?
    /// The other routes it flies besides `routeID` (see SharedAircraft.swift); missing from older saves.
    var otherRoutesStore: [Int]?
    /// The other routes it goes back to after a job; missing from older saves.
    var returnOtherRoutesStore: [Int]?

    public var eventMinute: Int? {
        switch status {
        case .boarding(let t), .flying(let t), .maintenance(let t), .onOrder(let t): return t
        case .idle, .grounded: return nil
        }
    }

    public func ageYears(atDay day: Int) -> Double { Double(day - builtDay) / 365.25 }

    public var type: AircraftType? { AircraftCatalog.type(typeID) }

    public var isDelivered: Bool {
        if case .onOrder = status { return false }
        return true
    }
}
