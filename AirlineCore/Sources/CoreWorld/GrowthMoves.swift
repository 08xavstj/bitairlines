// CoreWorld/GrowthMoves.swift: moving the headquarters to a bigger airport, and trading in an aircraft for a bigger one.
// Numbers are in the Tuning block of Growth.swift. Codes and numbers only; the app writes the words.
import CoreCatalog

/// An airport the headquarters could move to, and what the move costs.
public struct HeadquartersOption: Sendable, Hashable, Identifiable {
    public var code: String
    public var fee: Int
    public var id: String { code }
}

extension World {
    // MARK: Moving the headquarters

    /// What moving the headquarters to this airport costs: a fee per certificate level, more at bigger airports.
    public func headquartersFee(to airport: Airport) -> Int {
        Int((Double(Tuning.headquartersFeePerLevel * airline.level) * World.sizeFactor(airport)).rounded())
    }

    /// Why the headquarters cannot move here (nil if it can).
    public func headquartersProblem(to code: String) -> WorldError? {
        guard let airport = AirportCatalog.airport(code) else { return .unknownAirport(code) }
        if code == airline.home { return .invalidChoice }
        if airline.level < Tuning.headquartersMoveLevel { return .levelTooLow(required: Tuning.headquartersMoveLevel) }
        let required = Progression.requiredLevel(for: airport)
        if required > airline.level { return .airportLevelTooHigh(airport: code, required: required) }
        if !airline.permits.contains(airport.country) { return .permitRequired(country: airport.country, price: permitPrice(country: airport.country)) }
        let fee = headquartersFee(to: airport)
        if airline.cash < fee { return .notEnoughCash(needed: fee) }
        return nil
    }

    /// The best places to move the headquarters: the biggest airports of the network the airline may use at its level, biggest first.
    /// Cash is not checked here, so the app can show the fee of a move the airline cannot pay for yet.
    public func headquartersOptions(limit: Int = 6) -> [HeadquartersOption] {
        let candidates = networkAirports.compactMap { AirportCatalog.airport($0) }.filter { airport in
            airport.code != airline.home && Progression.requiredLevel(for: airport) <= airline.level && airline.permits.contains(airport.country)
        }
        let ordered = candidates.sorted { $0.population != $1.population ? $0.population > $1.population : $0.code < $1.code }
        return ordered.prefix(max(0, limit)).map { HeadquartersOption(code: $0.code, fee: headquartersFee(to: $0)) }
    }

    /// Moves the headquarters. Everything else stays: routes, bases and aircraft where they are (aircraft parked at the old home can be ferried).
    /// Aircraft bought from now on, and those still on order that can land there, are delivered to the new home.
    public mutating func moveHeadquarters(to code: String) throws {
        if let problem = headquartersProblem(to: code) { throw problem }
        guard let airport = AirportCatalog.airport(code) else { throw WorldError.unknownAirport(code) }
        let fee = headquartersFee(to: airport)
        spendOnInvestment(fee)
        airline.home = code
        for i in aircraft.indices where !aircraft[i].isDelivered {
            if let type = aircraft[i].type, canUse(type: type, at: airport) { aircraft[i].location = code }
        }
        refreshJobArea()
        addNews(.growth, subject: "hq:" + code, amount: fee)
    }

    // MARK: Trading in an aircraft

    /// Why this aircraft cannot be traded in (nil if it can): it must be delivered, off every route and job, on the ground and not grounded.
    public func tradeInProblem(aircraftID: Int) -> WorldError? {
        guard let plane = aircraft.first(where: { $0.id == aircraftID }) else { return .unknownAircraft(aircraftID) }
        guard plane.isDelivered else { return .notDelivered }
        guard plane.routeID == nil else { return .aircraftHasRoute }
        guard plane.jobID == nil else { return .aircraftBusy }
        switch plane.status {
        case .flying, .grounded: return .aircraftBusy
        case .idle, .boarding, .maintenance, .onOrder: return nil
        }
    }

    /// Trades an aircraft in for a used one from the market: the dealer's price for the old one counts towards the new one. Returns the new aircraft's id.
    @discardableResult
    public mutating func tradeIn(aircraftID: Int, forListing listingID: Int) throws -> Int {
        if let problem = tradeInProblem(aircraftID: aircraftID) { throw problem }
        var copy = self
        try copy.sell(aircraftID: aircraftID)
        let id = try copy.buyUsed(listingID: listingID)
        self = copy
        return id
    }

    /// Trades an aircraft in for a new one from the factory. Returns the new aircraft's id.
    @discardableResult
    public mutating func tradeIn(aircraftID: Int, forNewType typeID: String) throws -> Int {
        if let problem = tradeInProblem(aircraftID: aircraftID) { throw problem }
        var copy = self
        try copy.sell(aircraftID: aircraftID)
        let id = try copy.orderNew(typeID: typeID)
        self = copy
        return id
    }
}
