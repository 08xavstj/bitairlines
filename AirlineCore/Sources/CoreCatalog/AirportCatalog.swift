// CoreCatalog/AirportCatalog.swift: every playable airport, parsed once from the generated rows in Data/.
import CoreSim

public enum AirportCatalog {
    public static let all: [Airport] = AirportRows.groups.flatMap { group in
        group.split(separator: "\n").compactMap { Airport(row: $0) }
    }

    public static let byCode: [String: Airport] = Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })

    /// Towns taken off the map (road towns near a city, see tools/data/declutter.py). Not offered anywhere, but an older save
    /// that flies to one still finds it.
    public static let retired: [String: Airport] = Dictionary(uniqueKeysWithValues: AirportRows_Retired.rows.split(separator: "\n").compactMap { Airport(row: $0) }.map { ($0.code, $0) })

    public static func airport(_ code: String) -> Airport? { byCode[code] ?? retired[code] }

    public static func inCountry(_ country: String) -> [Airport] { all.filter { $0.country == country } }

    public static func inGroup(_ group: RegionGroup) -> [Airport] {
        all.filter { CountryCatalog.country($0.country)?.group == group }
    }

    /// The `limit` airports closest to a point, nearest first. Ties break on the code, so the answer never depends on hash order.
    public static func nearest(latitude: Double, longitude: Double, limit: Int, where keep: (Airport) -> Bool = { _ in true }) -> [Airport] {
        let ranked = all.filter(keep).map { airport in
            (airport, GeoMath.distanceKm(lat1: latitude, lon1: longitude, lat2: airport.latitude, lon2: airport.longitude))
        }
        return ranked.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.code < $1.0.code }.prefix(limit).map { $0.0 }
    }
}
