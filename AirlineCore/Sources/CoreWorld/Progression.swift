// CoreWorld/Progression.swift: certificate levels, what they unlock and what they cost. Level 1 is a bush operator; level 7 flies jumbos worldwide.
import CoreCatalog

public struct LevelRequirement: Sendable, Hashable {
    /// The level this requirement leads to.
    public let level: Int
    public let lifetimeRevenue: Int
    public let reputation: Double
    /// Paid to the regulator when upgrading.
    public let fee: Int
}

public enum Progression {
    /// Index 0 leads to level 2.
    public static let requirements: [LevelRequirement] = [
        LevelRequirement(level: 2, lifetimeRevenue: 1_500_000, reputation: 12, fee: 150_000),
        LevelRequirement(level: 3, lifetimeRevenue: 10_000_000, reputation: 22, fee: 600_000),
        LevelRequirement(level: 4, lifetimeRevenue: 60_000_000, reputation: 35, fee: 3_000_000),
        LevelRequirement(level: 5, lifetimeRevenue: 400_000_000, reputation: 50, fee: 15_000_000),
        LevelRequirement(level: 6, lifetimeRevenue: 2_500_000_000, reputation: 65, fee: 60_000_000),
        LevelRequirement(level: 7, lifetimeRevenue: 12_000_000_000, reputation: 78, fee: 200_000_000),
    ]

    public static func requirement(forNextLevelAfter level: Int) -> LevelRequirement? {
        level >= Airline.maxLevel ? nil : requirements[level - 1]
    }

    public static func meets(_ r: LevelRequirement, airline: Airline) -> Bool {
        airline.stats.revenue >= r.lifetimeRevenue && airline.reputation >= r.reputation
    }

    /// The lowest certificate level that may fly into an airport: bigger catchments are busier and slot-controlled.
    public static func requiredLevel(for airport: Airport) -> Int {
        let pop = airport.population
        let base: Int
        switch pop {
        case 12_000_000...: base = 6
        case 5_000_000...: base = 5
        case 1_500_000...: base = 4
        case 400_000...: base = 3
        case 80_000...: base = 2
        default: base = 1
        }
        return airport.kind == .large ? max(base, 2) : base
    }

    /// Cost of an operating permit for a country: richer countries charge far more.
    public static func permitPrice(country: String) -> Int {
        let wealth = CountryCatalog.country(country)?.wealth ?? 3
        return 40_000 * wealth * wealth
    }
}
