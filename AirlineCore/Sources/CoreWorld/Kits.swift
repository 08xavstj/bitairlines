// CoreWorld/Kits.swift: changes fitted to one aircraft: floats, amphibious floats, wheel-skis, a gravel kit, a STOL kit, a freight
// conversion. Fitting one takes the aircraft out of service for a few days.
import CoreCatalog

public enum Kit: String, Sendable, Hashable, Codable, CaseIterable {
    /// Lakes and rivers only.
    case floats
    /// Lakes and runways.
    case amphibious
    /// Frozen lakes in winter, as well as runways.
    case wheelSkis
    /// Gravel strips for an aircraft built for tarmac.
    case gravelKit
    /// Needs a quarter less runway.
    case stolKit
    /// Seats out, freight in.
    case freighter

    /// The kinds of aircraft each kit is made for.
    public func fits(_ type: AircraftType) -> Bool {
        switch self {
        case .floats, .amphibious: return [.lightSingle, .utilitySingle, .twinTurboprop].contains(type.family) && !type.water
        case .wheelSkis: return [.lightSingle, .utilitySingle, .twinTurboprop, .taildragger, .commuter].contains(type.family) && !type.water
        case .gravelKit: return [.regionalJet, .rearEngineMainline, .narrowbody, .regionalTurboprop].contains(type.family) && !type.gravel
        case .stolKit: return type.engine != .jet && !type.water
        case .freighter: return type.seats > 0
        }
    }

    /// Kits that cannot be fitted together (one set of landing gear at a time).
    public var exclusiveWith: [Kit] {
        switch self {
        case .floats: [.amphibious, .wheelSkis]
        case .amphibious: [.floats, .wheelSkis]
        case .wheelSkis: [.floats, .amphibious]
        case .gravelKit, .stolKit, .freighter: []
        }
    }

    /// Price as a share of the type's new price.
    public var priceShare: Double {
        switch self {
        case .floats: 0.08
        case .amphibious: 0.15
        case .wheelSkis: 0.04
        case .gravelKit: 0.03
        case .stolKit: 0.05
        case .freighter: 0.06
        }
    }

    /// Days in the hangar to fit it.
    public var days: Int {
        switch self {
        case .floats, .stolKit: 3
        case .amphibious: 4
        case .wheelSkis: 2
        case .gravelKit: 5
        case .freighter: 10
        }
    }
}

extension Aircraft {
    public var kits: [Kit] {
        get { kitsStore ?? [] }
        set { kitsStore = newValue.isEmpty ? nil : Kit.allCases.filter { newValue.contains($0) } }
    }

    public var capability: Capability? { type.map { Capability(type: $0, kits: kits) } }

    /// Seats as fitted (none once converted to a freighter).
    public var seats: Int { kits.contains(.freighter) ? 0 : (type?.seats ?? 0) }

    /// Freight capacity as fitted (a freighter carries about 95 kg where each seat was).
    public var cargoKg: Int { (type?.cargoKg ?? 0) + (kits.contains(.freighter) ? (type?.seats ?? 0) * 95 : 0) }
}

extension World {
    public func kitPrice(_ kit: Kit, type: AircraftType) -> Int { Int(Double(type.priceUSD) * kit.priceShare) }

    /// Why this kit cannot be fitted to this aircraft now (nil if it can).
    public func kitProblem(_ kit: Kit, aircraftID: Int) -> WorldError? {
        guard let i = aircraftIndex(aircraftID) else { return .unknownAircraft(aircraftID) }
        guard let type = aircraft[i].type else { return .unknownType(aircraft[i].typeID) }
        if aircraft[i].kits.contains(kit) { return .alreadyBuilt }
        if !kit.fits(type) { return .kitDoesNotFit }
        switch aircraft[i].status {
        case .flying, .onOrder, .grounded, .maintenance: return .aircraftBusy
        case .idle, .boarding: break
        }
        if aircraft[i].jobID != nil { return .aircraftBusy }
        let price = kitPrice(kit, type: type)
        if airline.cash < price { return .notEnoughCash(needed: price) }
        return nil
    }

    /// Fits a kit (replacing any kit it cannot be fitted with). The aircraft spends a few days in the hangar, and leaves a route
    /// it can no longer fly.
    public mutating func fit(_ kit: Kit, aircraftID: Int) throws {
        if let problem = kitProblem(kit, aircraftID: aircraftID) { throw problem }
        guard let i = aircraftIndex(aircraftID), let type = aircraft[i].type else { throw WorldError.unknownAircraft(aircraftID) }
        spendOnInvestment(kitPrice(kit, type: type))
        aircraft[i].kits = aircraft[i].kits.filter { !kit.exclusiveWith.contains($0) } + [kit]
        aircraft[i].status = .maintenance(until: clock.minute + kit.days * GameClock.minutesPerDay)
        addNews(.kitFitted, subject: aircraft[i].registration, amount: Kit.allCases.firstIndex(of: kit) ?? 0)
        leaveRouteIfItNoLongerFits(i)
    }

    /// Takes a kit off again (free, one day in the hangar).
    public mutating func remove(_ kit: Kit, aircraftID: Int) throws {
        guard let i = aircraftIndex(aircraftID) else { throw WorldError.unknownAircraft(aircraftID) }
        guard aircraft[i].kits.contains(kit) else { throw WorldError.invalidChoice }
        switch aircraft[i].status {
        case .flying, .onOrder, .grounded, .maintenance: throw WorldError.aircraftBusy
        case .idle, .boarding: break
        }
        aircraft[i].kits = aircraft[i].kits.filter { $0 != kit }
        aircraft[i].status = .maintenance(until: clock.minute + GameClock.minutesPerDay)
        leaveRouteIfItNoLongerFits(i)
    }

    /// Takes the aircraft off each of its routes it can no longer fly (a shared aircraft keeps the ones that still fit).
    mutating func leaveRouteIfItNoLongerFits(_ i: Int) {
        guard let type = aircraft[i].type else { return }
        let kits = aircraft[i].kits
        for rid in aircraft[i].allRouteIDs {
            guard let r = routeIndex(rid) else { continue }
            if fitProblem(type: type, route: routes[r], kits: kits) != nil { detach(i, fromRoute: rid) }
        }
    }
}
