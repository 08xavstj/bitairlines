// CoreWorld/Route.swift: a route is a cycle of stops; assigned aircraft fly its legs one after another, forever.
//   Stops A, B, C make legs A->B, B->C and C->A. Two stops make A->B and B->A.
// Each leg has a "waiting bucket" of passengers and freight that fills while no aircraft is there and is emptied by boarding.

public struct LegState: Sendable, Hashable, Codable {
    public var from: String
    public var to: String
    public var distanceKm: Double
    /// Passengers per day wanting this leg, all airlines together (before seasons and our share of the market).
    public var marketPaxPerDay: Double
    public var marketCargoKgPerDay: Double
    /// The going one-way fare in dollars; the route's fare multiplier scales it.
    public var marketFare: Double
    public var waitingPax: Double
    public var waitingCargoKg: Double
    /// Minute the buckets were last brought up to date.
    public var lastUpdate: Int
    /// 0.5...1.0: a new route takes time to build awareness; good service raises it.
    public var maturity: Double
    public var passengersCarried: Int
    public var revenue: Int
    /// Departures on this leg in the current and the previous week, for the frequency the market sees.
    public var departuresThisWeek: Int
    public var departuresLastWeek: Int
    /// Earliest minute the next departure on this leg is allowed (the schedule slot).
    public var nextSlot: Int
}

public struct Route: Sendable, Hashable, Codable, Identifiable {
    public var id: Int
    public var name: String
    public var stops: [String]
    /// Multiplies the going fare (0.5...2.0).
    public var fareMultiplier: Double
    public var carriesCargo: Bool
    /// Departures per day on each leg (0.25 is one every four days). Aircraft wait for the next slot, so the schedule matches demand.
    public var frequency: Double
    /// True until the player sets the frequency by hand: while true, assigning aircraft picks a sensible schedule.
    public var autoFrequency: Bool
    public var legs: [LegState]
    public var aircraftIDs: [Int]
    public var openedDay: Int
    public var flights: Int
    public var revenueThisMonth: Int
    public var costThisMonth: Int
    public var revenueLastMonth: Int
    public var costLastMonth: Int

    public static let minFare = 0.5
    public static let maxFare = 2.0
    public static let minFrequency = 0.25
    public static let maxFrequency = 24.0
    /// The schedules offered in the app and picked by the suggestion.
    public static let frequencySteps: [Double] = [0.25, 0.5, 1, 1.5, 2, 3, 4, 5, 6, 8, 10, 12, 16, 24]

    /// Minutes between departures on one leg.
    public var headwayMinutes: Int { max(1, Int((Double(GameClock.minutesPerDay) / frequency).rounded())) }

    public var legCount: Int { stops.count }

    /// Index of the leg that starts at the airport, if the route serves it.
    public func firstLeg(from airport: String) -> Int? { stops.firstIndex(of: airport) }
}
