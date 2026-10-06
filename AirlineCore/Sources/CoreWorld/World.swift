// CoreWorld/World.swift: the whole live game: the airline, its fleet and routes, the market, the clock. Plain Codable value: a save is this, encoded.
// Everything that changes it is a mutating method on World (see FleetActions, RouteActions, Simulation, IssueActions).
import CoreCatalog
import CoreSim

public struct DayBook: Sendable, Hashable, Codable {
    public var day: Int
    public var revenue: Int
    public var flightCosts: Int
    public var overhead: Int
    /// Money put into the airline that day (aircraft, bases, kits, slots, training, permits, certificates). Older saves lack it.
    public var investmentStore: Int?
    public var investments: Int {
        get { investmentStore ?? 0 }
        set { investmentStore = newValue }
    }
    /// The day's operating result: what flying earned less what running the airline cost. Investments are not in it.
    public var net: Int { revenue - flightCosts - overhead }
}

public struct World: Sendable, Codable {
    public var rulesVersion: Int
    public var rng: SeededRandom
    public var clock: GameClock
    public var airline: Airline
    public var aircraft: [Aircraft]
    public var routes: [Route]
    public var issues: [Issue]
    public var market: Market
    public var news: [NewsItem]
    public var pausePolicy: PausePolicy
    /// The last few months of daily results, oldest first.
    public var books: [DayBook]
    public internal(set) var today: DayBook
    var nextAircraftID: Int
    var nextRouteID: Int
    var nextIssueID: Int
    var nextLoanID: Int
    /// Consecutive days with cash below the overdraft limit.
    var daysOverdrawn: Int
    public var isBankrupt: Bool
    /// The highest certificate level the player has already been told they qualify for.
    var announcedLevel: Int
    /// The systems added after the first version (see Operations.swift). Missing from older saves; use `ops`.
    var operationsStore: Operations?

    public static let newsLimit = 120
    public static let bookLimit = 180

    // MARK: Lookups

    public func aircraftIndex(_ id: Int) -> Int? { aircraft.firstIndex { $0.id == id } }
    public func routeIndex(_ id: Int) -> Int? { routes.firstIndex { $0.id == id } }
    public func issueIndex(_ id: Int) -> Int? { issues.firstIndex { $0.id == id } }

    public var homeCountry: String { AirportCatalog.airport(airline.home)?.country ?? "US" }

    /// True while an issue that stops the game is waiting for the player.
    public var isPausedByIssue: Bool { issues.contains { $0.pausesGame } }

    // MARK: Bookkeeping helpers

    mutating func addNews(_ kind: NewsItem.Kind, subject: String, amount: Int = 0) {
        news.append(NewsItem(minute: clock.minute, kind: kind, subject: subject, amount: amount))
        if news.count > World.newsLimit { news.removeFirst(news.count - World.newsLimit) }
    }

    mutating func earn(_ amount: Int) {
        airline.cash += amount
        airline.stats.revenue += amount
        today.revenue += amount
    }

    mutating func spendOnFlights(_ amount: Int) {
        airline.cash -= amount
        airline.stats.expenses += amount
        today.flightCosts += amount
    }

    /// Money spent on something the airline keeps (an aircraft, a base, a kit): out of the bank, but not an operating cost.
    mutating func spendOnInvestment(_ amount: Int) {
        airline.cash -= amount
        airline.stats.expenses += amount
        today.investments += amount
    }

    mutating func spendOnOverhead(_ amount: Int) {
        airline.cash -= amount
        airline.stats.expenses += amount
        today.overhead += amount
    }

    /// A registration no aircraft in the fleet already wears.
    mutating func nextRegistration() -> String {
        let country = homeCountry
        while true {
            let candidate = Registration.make(country: country, rng: &rng)
            if !aircraft.contains(where: { $0.registration == candidate }) { return candidate }
        }
    }
}
