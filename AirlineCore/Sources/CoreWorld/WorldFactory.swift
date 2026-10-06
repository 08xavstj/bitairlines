// CoreWorld/WorldFactory.swift: starting a new game, the starter aircraft offers, and the used-aircraft market.
import CoreCatalog
import CoreSim

public enum Difficulty: String, Sendable, Hashable, Codable, CaseIterable {
    case easy, standard, hard

    /// Money to start with, before buying the first aircraft.
    public var startingBudget: Int {
        switch self {
        case .easy: 6_000_000
        case .standard: 4_000_000
        case .hard: 2_500_000
        }
    }
}

/// A used aircraft the player may start with (a bush type of certificate level 1 that can use the home airport).
public struct StarterOffer: Sendable, Hashable, Identifiable {
    public var typeID: String
    public var ageYears: Double
    public var condition: Double
    public var price: Int
    public var id: String { typeID }
}

public struct NewGameConfig: Sendable {
    public var airlineName: String
    public var airlineCode: String
    public var homeAirport: String
    public var branding: Branding
    public var difficulty: Difficulty
    public var starterTypeID: String
    public var seed: UInt64

    public init(airlineName: String, airlineCode: String, homeAirport: String, branding: Branding, difficulty: Difficulty, starterTypeID: String, seed: UInt64) {
        self.airlineName = airlineName
        self.airlineCode = airlineCode
        self.homeAirport = homeAirport
        self.branding = branding
        self.difficulty = difficulty
        self.starterTypeID = starterTypeID
        self.seed = seed
    }
}

extension Aircraft {
    init(id: Int, typeID: String, registration: String, builtDay: Int, condition: Double, price: Int, location: String, status: AircraftStatus) {
        self.init(id: id, typeID: typeID, registration: registration, builtDay: builtDay, condition: condition, ownership: .owned,
                  purchasePrice: price, location: location, status: status, routeID: nil, legIndex: 0, flight: nil, livery: nil,
                  blockMinutesToday: 0, totalFlights: 0, totalBlockMinutes: 0)
    }
}

extension World {
    static let workingCapitalFloor = 600_000

    public static func starterOffers(home: String, difficulty: Difficulty) -> [StarterOffer] {
        guard let airport = AirportCatalog.airport(home) else { return [] }
        return AircraftCatalog.available(atLevel: 1).filter { $0.canLand(at: airport) }.compactMap { (type: AircraftType) -> StarterOffer? in
            let age = type.inProduction ? 12.0 : 45.0
            let price = Valuation.value(type: type, ageYears: age, condition: 78)
            return price <= difficulty.startingBudget - workingCapitalFloor ? StarterOffer(typeID: type.id, ageYears: age, condition: 78, price: price) : nil
        }
    }

    public static func newGame(_ config: NewGameConfig) throws -> World {
        guard let home = AirportCatalog.airport(config.homeAirport) else { throw WorldError.unknownAirport(config.homeAirport) }
        guard let type = AircraftCatalog.type(config.starterTypeID) else { throw WorldError.unknownType(config.starterTypeID) }
        guard type.level == 1 else { throw WorldError.levelTooLow(required: type.level) }
        guard type.canLand(at: home) else { throw WorldError.aircraftCannotUse(airport: home.code) }
        let offer = starterOffers(home: home.code, difficulty: config.difficulty).first { $0.typeID == type.id }
        guard let offer else { throw WorldError.notEnoughCash(needed: Valuation.value(type: type, ageYears: 12, condition: 78) + workingCapitalFloor) }

        let airline = Airline(name: config.airlineName, code: config.airlineCode, home: home.code, cash: config.difficulty.startingBudget - offer.price,
                              level: 1, reputation: 10, branding: config.branding, permits: [home.country], loans: [], stats: AirlineStats())
        var world = World(rulesVersion: WorldInfo.rulesVersion, rng: SeededRandom(seed: config.seed), clock: GameClock(minute: 6 * 60), airline: airline,
                          aircraft: [], routes: [], issues: [], market: Market(fuelIndex: 1.0, listings: [], nextListingID: 1, closures: []), news: [],
                          pausePolicy: .critical, books: [], today: DayBook(day: 0, revenue: 0, flightCosts: 0, overhead: 0),
                          nextAircraftID: 1, nextRouteID: 1, nextIssueID: 1, nextLoanID: 1, daysOverdrawn: 0, isBankrupt: false, announcedLevel: 1)
        let registration = world.nextRegistration()
        world.aircraft.append(Aircraft(id: world.takeAircraftID(), typeID: type.id, registration: registration, builtDay: -Int(offer.ageYears * 365.25),
                                       condition: offer.condition, price: offer.price, location: home.code, status: .idle))
        world.refreshListings()
        return world
    }

    mutating func takeAircraftID() -> Int { defer { nextAircraftID += 1 }; return nextAircraftID }
    mutating func takeRouteID() -> Int { defer { nextRouteID += 1 }; return nextRouteID }
    mutating func takeIssueID() -> Int { defer { nextIssueID += 1 }; return nextIssueID }
    mutating func takeLoanID() -> Int { defer { nextLoanID += 1 }; return nextLoanID }

    /// Fills the used-aircraft market with a fresh set of 22 listings.
    mutating func refreshListings() {
        market.listings = []
        addListings(22)
    }

    /// Weekly turnover: a few aircraft sell to other airlines and new ones come up.
    mutating func rotateListings() {
        for _ in 0..<min(6, market.listings.count) { market.listings.remove(at: rng.int(0...(market.listings.count - 1))) }
        addListings(6)
    }

    mutating func addListings(_ count: Int) {
        let types = AircraftCatalog.available(atLevel: airline.level + 1)
        let weights = types.map { $0.level <= airline.level ? 3.0 : 1.0 }
        for _ in 0..<count {
            let type = types[rng.weightedIndex(weights)]
            let age = type.inProduction ? rng.uniform(2, 30) : rng.uniform(25, 75)
            let condition = min(95, max(30, 100 - age + rng.uniform(-12, 8)))
            let value = Double(Valuation.value(type: type, ageYears: age, condition: condition))
            let price = Int((value * rng.uniform(0.92, 1.12)).rounded())
            market.listings.append(UsedListing(id: market.nextListingID, typeID: type.id, ageYears: age, condition: condition, price: price, deliveryDays: rng.int(2...9)))
            market.nextListingID += 1
        }
    }
}
