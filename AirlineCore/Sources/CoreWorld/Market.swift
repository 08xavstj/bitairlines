// CoreWorld/Market.swift: the outside world: fuel prices, used aircraft for sale, airport closures, seasons.
import CoreCatalog
import CoreSim

public struct UsedListing: Sendable, Hashable, Codable, Identifiable {
    public var id: Int
    public var typeID: String
    public var ageYears: Double
    public var condition: Double
    public var price: Int
    /// The seller's ferry estimate, 2 to 9. Kept under its old name so saves still load;
    /// the wait is `Valuation.usedDeliveryMinutes` (a few hours, not days).
    public var deliveryDays: Int
}

public struct Closure: Sendable, Hashable, Codable {
    public var airport: String
    public var untilMinute: Int
}

public struct Market: Sendable, Hashable, Codable {
    /// Fuel price relative to the baseline; drifts month by month.
    public var fuelIndex: Double
    public var listings: [UsedListing]
    public var nextListingID: Int
    public var closures: [Closure]
}

public enum Valuation {
    /// Share of the new price an aircraft of this age is worth. Jets lose value faster; types out of production hold a higher floor.
    public static func usedFactor(type: AircraftType, ageYears: Double) -> Double {
        let rate = type.engine == .jet ? 0.05 : 0.035
        let floor = type.inProduction ? 0.12 : 0.25
        return max(floor, 1.0 - rate * ageYears)
    }

    public static func value(type: AircraftType, ageYears: Double, condition: Double) -> Int {
        let base = Double(type.priceUSD) * usedFactor(type: type, ageYears: ageYears) * (0.7 + 0.3 * condition / 100.0)
        return Int(base.rounded())
    }

    /// Maintenance cost multiplier for an ageing or run-down aircraft (1.0 is a new one in perfect condition).
    public static func wearFactor(ageYears: Double, condition: Double) -> Double {
        min(2.2, 1.0 + 0.02 * ageYears) * (1.0 + (100.0 - condition) / 250.0)
    }

    /// Minutes until a used aircraft reaches the home airport: a ferry flight of a few hours.
    public static func usedDeliveryMinutes(_ listing: UsedListing) -> Int {
        listing.deliveryDays * Tuning.usedDeliveryHoursPerStep * 60
    }

    /// Minutes until a new aircraft is delivered: bigger types take a little longer.
    public static func newDeliveryMinutes(level: Int) -> Int {
        (Tuning.newDeliveryBaseHours + Tuning.newDeliveryHoursPerLevel * level) * 60
    }
}

public enum Seasons {
    /// Demand multiplier by calendar month (index 0 is January): summer peaks, winter dip, a December bump for visiting family.
    public static let byMonth: [Double] = [0.90, 0.90, 1.00, 1.00, 1.05, 1.15, 1.20, 1.20, 1.05, 1.00, 0.95, 1.05]

    public static func factor(month: Int) -> Double { byMonth[min(max(month, 1), 12) - 1] }
}
