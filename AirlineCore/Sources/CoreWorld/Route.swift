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
    /// Through passengers from hubs (see Hubs.swift); missing from older saves.
    var connectingPaxStore: Double?
    var connectingFareStore: Double?
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
    /// Service level (see Service.swift); missing from older saves, which read as standard.
    var serviceStore: ServiceLevel?
    /// The route's own money book (see `book`); missing from older saves, which start an empty one.
    var bookStore: RouteBook?

    public static let minFare = 0.5
    public static let maxFare = 2.0
    public static let minFrequency = 0.25
    public static let maxFrequency = 24.0
    /// The schedules offered in the app and picked by the suggestion.
    public static let frequencySteps: [Double] = [0.25, 0.5, 1, 1.5, 2, 3, 4, 5, 6, 8, 10, 12, 16, 24]

    /// The nearest schedule the app offers.
    public static func snapFrequency(_ f: Double) -> Double {
        frequencySteps.min { abs($0 - f) < abs($1 - f) } ?? 1
    }

    /// Minutes between departures on one leg.
    public var headwayMinutes: Int { max(1, Int((Double(GameClock.minutesPerDay) / frequency).rounded())) }

    public var legCount: Int { stops.count }

    /// Index of the leg that starts at the airport, if the route serves it.
    public func firstLeg(from airport: String) -> Int? { stops.firstIndex(of: airport) }
}

// MARK: The route's own books

/// Money and loads booked to a route over some days.
public struct RouteDay: Sendable, Hashable, Codable {
    public var revenue: Int
    /// Direct cost of the legs flown: fuel, crew, maintenance, landing, navigation, handling. Includes empty flights to reach the route.
    public var flightCost: Int
    /// The fixed daily cost (admin, insurance) of the aircraft assigned to the route. Head office is not included.
    public var aircraftCost: Int
    public var passengers: Int
    /// Seats flown: the seats of every aircraft that flew a leg, once per leg.
    public var seats: Int
    public var flights: Int

    public init(revenue: Int = 0, flightCost: Int = 0, aircraftCost: Int = 0, passengers: Int = 0, seats: Int = 0, flights: Int = 0) {
        self.revenue = revenue
        self.flightCost = flightCost
        self.aircraftCost = aircraftCost
        self.passengers = passengers
        self.seats = seats
        self.flights = flights
    }

    public var cost: Int { flightCost + aircraftCost }
    public var profit: Int { revenue - cost }
    /// Passengers as a share of seats flown; nil when no seats were flown.
    public var seatLoad: Double? { seats > 0 ? Double(passengers) / Double(seats) : nil }

    mutating func add(_ other: RouteDay) {
        revenue += other.revenue
        flightCost += other.flightCost
        aircraftCost += other.aircraftCost
        passengers += other.passengers
        seats += other.seats
        flights += other.flights
    }
}

/// A route's money: today, the finished days before it (up to a week together) and everything since it opened.
public struct RouteBook: Sendable, Hashable, Codable {
    /// Finished days, oldest first; at most `Route.bookDays - 1` of them.
    public var pastDays: [RouteDay] = []
    public var today = RouteDay()
    /// Everything booked since the route opened (since the game was updated, for routes in older saves).
    public var sinceOpened = RouteDay()

    public init() {}

    /// Today plus the finished days kept: the last `Route.bookDays` days, or fewer for a new route.
    public var recent: RouteDay {
        var sum = today
        for day in pastDays { sum.add(day) }
        return sum
    }

    /// How many days `recent` covers (1 on the first day).
    public var recentDays: Int { pastDays.count + 1 }

    mutating func add(_ day: RouteDay) {
        today.add(day)
        sinceOpened.add(day)
    }

    /// Midnight: today becomes a finished day; the oldest one drops off.
    mutating func closeDay() {
        pastDays.append(today)
        let keep = Route.bookDays - 1
        if pastDays.count > keep { pastDays.removeFirst(pastDays.count - keep) }
        today = RouteDay()
    }
}

extension Route {
    /// The rolling window of the route's books, in days.
    public static let bookDays = 7

    public internal(set) var book: RouteBook {
        get { bookStore ?? RouteBook() }
        set { bookStore = newValue }
    }

    /// The last 7 days, today included (fewer for a route that has not run that long, see `book.recentDays`).
    public var last7Days: RouteDay { book.recent }
    public var revenueLast7Days: Int { last7Days.revenue }
    /// Flight costs plus the assigned aircraft's fixed cost. Head office is not included.
    public var costLast7Days: Int { last7Days.cost }
    public var profitLast7Days: Int { last7Days.profit }
    /// Passengers as a share of seats flown; nil if nothing flew.
    public var seatLoadLast7Days: Double? { last7Days.seatLoad }

    public var sinceOpened: RouteDay { book.sinceOpened }
    public var profitSinceOpened: Int { sinceOpened.profit }
}
