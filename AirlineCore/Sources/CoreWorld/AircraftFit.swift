// CoreWorld/AircraftFit.swift: before buying, can this aircraft type use the airports the airline already flies to?
// For each airport it cannot use, what would change that (a kit, a base upgrade, a longer runway than can be built).
// Codes and numbers only; the app writes the words.
import CoreCatalog

/// One thing an aircraft type needs before it can use an airport.
public enum FitNeed: Sendable, Hashable {
    /// A lake: fit floats or amphibious floats.
    case floats
    /// A lake, and no float kit is made for this type.
    case cannotUseWater
    /// A runway, and this type is a floatplane.
    case cannotUseRunway
    /// Gravel: fit a gravel kit.
    case gravelKit
    /// Gravel, and no gravel kit is made for this type: pave the strip (a base upgrade).
    case paving
    /// The STOL kit cuts the runway it needs enough to fit.
    case stolKit
    /// A longer runway at a base would be enough.
    case runwayExtension
    /// The runway is this many feet too short, even with the kit and the extension.
    case runwayTooShort(byFt: Int)
}

/// Whether a type can use one airport, and if not, what it needs.
public struct AirportFit: Sendable, Hashable {
    public var code: String
    public var needs: [FitNeed]
    public var fits: Bool { needs.isEmpty }
}

/// How a type fits the whole network.
public struct AircraftFit: Sendable, Hashable {
    /// The certificate level needed to buy it, if higher than the airline's.
    public var levelNeeded: Int?
    /// One entry per airport the airline uses, home first.
    public var airports: [AirportFit]

    public var fitCount: Int { airports.filter(\.fits).count }
    public var fitsAll: Bool { fitCount == airports.count }
    public var fitsAny: Bool { fitCount > 0 }
    public var misfits: [AirportFit] { airports.filter { !$0.fits } }
}

extension World {
    /// The airports the airline uses: home first, then route stops and bases in code order.
    public var networkAirports: [String] {
        var others = Set(routes.flatMap(\.stops))
        for b in ops.bases { others.insert(b.airport) }
        others.remove(airline.home)
        return [airline.home] + others.sorted()
    }

    /// How a type, as delivered with no kits, fits the airline's airports.
    public func fit(of type: AircraftType) -> AircraftFit {
        let fits = networkAirports.compactMap { code in
            AirportCatalog.airport(code).map { AirportFit(code: code, needs: needs(of: type, at: $0)) }
        }
        return AircraftFit(levelNeeded: type.level > airline.level ? type.level : nil, airports: fits)
    }

    /// What a type with no kits needs to use an airport in any season (empty if it can already).
    public func needs(of type: AircraftType, at airport: Airport) -> [FitNeed] {
        if canUse(type: type, at: airport) { return [] }
        let surf = surface(at: airport)
        if surf == .water { return [Kit.floats.fits(type) ? .floats : .cannotUseWater] }
        if !type.paved && !type.gravel { return [.cannotUseRunway] }
        var needs: [FitNeed] = []
        if surf == .gravel && !type.gravel { needs.append(Kit.gravelKit.fits(type) ? .gravelKit : .paving) }
        if ops.mode.checksRunways { needs += runwayNeeds(of: type, at: airport) }
        return needs
    }

    /// The cheapest way to make the runway long enough, or how far short it stays.
    func runwayNeeds(of type: AircraftType, at airport: Airport) -> [FitNeed] {
        let have = runwayFt(at: airport)
        let need = type.runwayFt
        if have >= need { return [] }
        let stol = Kit.stolKit.fits(type)
        let stolNeed = stol ? need * 3 / 4 : need
        let canExtend = base(at: airport.code)?.has(.runwayExtension) != true
        let extended = have + (canExtend ? Tuning.runwayExtensionFt : 0)
        if stol && have >= stolNeed { return [.stolKit] }
        if canExtend && extended >= need { return [.runwayExtension] }
        if stol && canExtend && extended >= stolNeed { return [.stolKit, .runwayExtension] }
        return [.runwayTooShort(byFt: stolNeed - extended)]
    }
}
