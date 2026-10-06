// CoreWorld/Airline.swift: the player's airline: identity, money, certificate level and reputation.

public struct Loan: Sendable, Hashable, Codable, Identifiable {
    public var id: Int
    public var remaining: Int
    /// Yearly interest rate, for example 0.08.
    public var annualRate: Double
    /// Paid back each month, plus interest on what is still owed (so payments shrink over time).
    public var monthlyPrincipal: Int
    public var monthsLeft: Int
}

public struct AirlineStats: Sendable, Hashable, Codable {
    public var passengers = 0
    public var cargoKg = 0
    public var flights = 0
    public var revenue = 0
    public var expenses = 0
}

public struct Airline: Sendable, Hashable, Codable {
    public var name: String
    /// Two or three letters shown on flight numbers, for example "LT".
    public var code: String
    /// IATA code of the headquarters airport.
    public var home: String
    public var cash: Int
    /// Certificate level 1...7: unlocks aircraft sizes and bigger cities.
    public var level: Int
    /// 0...100.
    public var reputation: Double
    public var branding: Branding
    /// Countries (ISO codes) the airline may operate in. The home country is always included.
    public var permits: [String]
    public var loans: [Loan]
    public var stats: AirlineStats

    public static let maxLevel = 7
}
