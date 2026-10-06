// CoreWorld/Collections.swift: the logbook. Every aircraft type flown (with the game day of its first flight), every airport
// landed at (first day and how many landings), and every rare find bought. Recorded from `arrive` and `buyUsed`.
// Stored in Operations; an older save starts with an empty logbook and fills it from its next landing.
import CoreCatalog

/// One airport in the logbook.
public struct AirportStamp: Sendable, Hashable, Codable {
    /// Game day index of the first landing.
    public var firstDay: Int
    public var landings: Int
}

/// A rare find the airline bought.
public struct RareFindEntry: Sendable, Hashable, Codable {
    public var kind: RareFind
    public var typeID: String
    /// Game day index it was bought.
    public var day: Int
}

public struct Logbook: Sendable, Hashable, Codable {
    /// Aircraft type id to the game day of its first flight.
    public var types: [String: Int] = [:]
    /// Airport code to its stamp.
    public var airports: [String: AirportStamp] = [:]
    public var rareFinds: [RareFindEntry] = []

    public init() {}

    enum CodingKeys: String, CodingKey { case types, airports, rareFinds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        types = try c.decodeIfPresent([String: Int].self, forKey: .types) ?? [:]
        airports = try c.decodeIfPresent([String: AirportStamp].self, forKey: .airports) ?? [:]
        rareFinds = try c.decodeIfPresent([RareFindEntry].self, forKey: .rareFinds) ?? []
    }

    /// Type ids flown, oldest first (ties by id).
    public var typesInOrder: [(typeID: String, firstDay: Int)] {
        types.map { (typeID: $0.key, firstDay: $0.value) }.sorted { ($0.firstDay, $0.typeID) < ($1.firstDay, $1.typeID) }
    }

    /// Airports landed at, by code.
    public var airportCodes: [String] { airports.keys.sorted() }

    /// Airports landed at per country (ISO code), most first (ties by code).
    public var countriesVisited: [(country: String, airports: Int)] {
        var counts: [String: Int] = [:]
        for code in airports.keys {
            guard let airport = AirportCatalog.airport(code) else { continue }
            counts[airport.country, default: 0] += 1
        }
        return counts.map { (country: $0.key, airports: $0.value) }.sorted { ($1.airports, $0.country) < ($0.airports, $1.country) }
    }

    /// Airports landed at per world region, most first (ties by name).
    public var regionsVisited: [(region: RegionGroup, airports: Int)] {
        var counts: [RegionGroup: Int] = [:]
        for (country, n) in countriesVisited {
            guard let group = CountryCatalog.country(country)?.group else { continue }
            counts[group, default: 0] += n
        }
        return counts.map { (region: $0.key, airports: $0.value) }.sorted { ($1.airports, $0.region.rawValue) < ($0.airports, $1.region.rawValue) }
    }
}

// MARK: Logbook
extension Tuning {
    /// Airports landed at for each Game Center achievement.
    public static let logbookAirportMilestones = [10, 50, 250]
    /// Types flown for the Game Center achievement.
    public static let logbookTypeMilestones = [10]
}

extension World {
    public var logbook: Logbook { ops.logbook }

    /// Records a landing: the aircraft's type and the airport. Ferry flights count (the aircraft did land there).
    mutating func logLanding(aircraftIndex i: Int, at code: String) {
        let typeID = aircraft[i].typeID
        let today = clock.dayIndex
        if ops.logbook.types[typeID] == nil { ops.logbook.types[typeID] = today }
        if var stamp = ops.logbook.airports[code] {
            stamp.landings += 1
            ops.logbook.airports[code] = stamp
        } else {
            ops.logbook.airports[code] = AirportStamp(firstDay: today, landings: 1)
        }
    }

    /// Records a rare find bought from the market (FleetActions.buyUsed).
    mutating func logRareFind(_ kind: RareFind, typeID: String) {
        ops.logbook.rareFinds.append(RareFindEntry(kind: kind, typeID: typeID, day: clock.dayIndex))
    }
}
