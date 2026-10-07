// CoreWorld/Bases.swift: bases the airline builds at airports it serves: a fuel depot, a hangar, runway lights, a longer runway,
// paving, a hub terminal. Each costs money to build and a little every day to keep.
import CoreCatalog

public enum Facility: String, Sendable, Hashable, Codable, CaseIterable {
    /// No remote fuel premium here, room to stock fuel ahead, and fuel for sale in Realism.
    case fuelDepot
    /// Scheduled checks here take half as long and repairs cost less.
    case hangar
    /// Flights in the dark at a strip that has no lights.
    case lights
    /// A longer runway, so bigger aircraft fit.
    case runwayExtension
    /// Gravel turned into tarmac, for aircraft that need a paved runway.
    case paving
    /// Lets passengers change planes here (connecting passengers between routes).
    case hubTerminal

    /// Build price at a small strip, in dollars; bigger airports cost more.
    public var basePrice: Int {
        switch self {
        case .fuelDepot: 180_000
        case .hangar: 450_000
        case .lights: 90_000
        case .runwayExtension: 600_000
        case .paving: 1_200_000
        case .hubTerminal: 900_000
        }
    }

    /// Upkeep per day at a small strip, in dollars.
    public var baseUpkeep: Int {
        switch self {
        case .fuelDepot: 30
        case .hangar: 60
        case .lights: 25
        case .runwayExtension: 80
        case .paving: 100
        case .hubTerminal: 300
        }
    }
}

public struct Base: Sendable, Hashable, Codable, Identifiable {
    public var airport: String
    /// In the order of Facility.allCases.
    public var facilities: [Facility]
    public var openedDay: Int

    public var id: String { airport }
    public func has(_ facility: Facility) -> Bool { facilities.contains(facility) }
}

extension World {
    static func sizeFactor(_ airport: Airport) -> Double {
        switch airport.kind {
        case .large: 3.0
        case .medium: 1.5
        case .small: 1.0
        case .seaplane: 0.8
        }
    }

    public func facilityPrice(_ facility: Facility, at airport: Airport) -> Int {
        Int(Double(facility.basePrice) * World.sizeFactor(airport))
    }

    public func facilityUpkeep(_ facility: Facility, at airport: Airport) -> Int {
        Int(Double(facility.baseUpkeep) * World.sizeFactor(airport))
    }

    /// Why this facility cannot be built here (nil if it can).
    public func facilityProblem(_ facility: Facility, at code: String) -> WorldError? {
        guard let airport = AirportCatalog.airport(code) else { return .unknownAirport(code) }
        if base(at: code)?.has(facility) == true { return .alreadyBuilt }
        if !airline.permits.contains(airport.country) { return .permitRequired(country: airport.country, price: permitPrice(country: airport.country)) }
        let required = Progression.requiredLevel(for: airport)
        if code != airline.home && required > airline.level { return .airportLevelTooHigh(airport: code, required: required) }
        switch facility {
        case .lights, .runwayExtension:
            if airport.surface == .water { return .cannotBuildHere }
        case .paving:
            if airport.surface != .gravel { return .cannotBuildHere }
        case .hubTerminal:
            if airline.level < 2 { return .levelTooLow(required: 2) }
        case .fuelDepot, .hangar:
            break
        }
        if facility == .lights && isLit(airport) { return .alreadyBuilt }
        let price = facilityPrice(facility, at: airport)
        if airline.cash < price { return .notEnoughCash(needed: price) }
        return nil
    }

    /// Builds a facility at an airport, opening a base there if there is none yet.
    public mutating func build(_ facility: Facility, at code: String) throws {
        if let problem = facilityProblem(facility, at: code) { throw problem }
        guard let airport = AirportCatalog.airport(code) else { throw WorldError.unknownAirport(code) }
        spendOnInvestment(facilityPrice(facility, at: airport))
        if let b = ops.bases.firstIndex(where: { $0.airport == code }) {
            ops.bases[b].facilities.append(facility)
            ops.bases[b].facilities.sort { Facility.allCases.firstIndex(of: $0)! < Facility.allCases.firstIndex(of: $1)! }
        } else {
            ops.bases.append(Base(airport: code, facilities: [facility], openedDay: clock.dayIndex))
            ops.bases.sort { $0.airport < $1.airport }
        }
        addNews(.baseBuilt, subject: code, amount: Facility.allCases.firstIndex(of: facility) ?? 0)
        refreshJobArea()
    }

    /// Closes a facility (nothing is paid back). The base goes when its last facility does.
    public mutating func demolish(_ facility: Facility, at code: String) throws {
        guard let b = ops.bases.firstIndex(where: { $0.airport == code }), ops.bases[b].has(facility) else { throw WorldError.invalidChoice }
        ops.bases[b].facilities.removeAll { $0 == facility }
        if ops.bases[b].facilities.isEmpty { ops.bases.remove(at: b) }
        // Without the longer runway or the paving, some aircraft may no longer fit this airport's routes.
        for i in aircraft.indices where aircraft[i].allRouteIDs.contains(where: { rid in routes.first { $0.id == rid }?.stops.contains(code) == true }) {
            leaveRouteIfItNoLongerFits(i)
        }
        refreshConnections()
    }

    /// What all bases cost per day.
    public var baseUpkeepPerDay: Int {
        ops.bases.reduce(0) { total, b in
            guard let airport = AirportCatalog.airport(b.airport) else { return total }
            return total + b.facilities.reduce(0) { $0 + facilityUpkeep($1, at: airport) }
        }
    }

    /// Airports where the remote fuel premium does not apply (the airline's fuel depots).
    var depotAirports: [String] { ops.bases.filter { $0.has(.fuelDepot) }.map(\.airport) }

    func hasHangar(at code: String) -> Bool { base(at: code)?.has(.hangar) == true }
}
