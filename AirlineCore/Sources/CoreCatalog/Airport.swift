// CoreCatalog/Airport.swift: one real airport (static data, never changes during a game).
import CoreSim

public enum RunwaySurface: String, Sendable, Hashable, Codable {
    case paved = "P", gravel = "G", water = "W"
}

public enum AirportKind: String, Sendable, Hashable, Codable {
    case large = "L", medium = "M", small = "S", seaplane = "W"
}

public struct Airport: Sendable, Hashable, Identifiable {
    /// IATA code (unique across the catalog). The save file refers to airports by this code.
    public let code: String
    public let icao: String
    public let name: String
    public let city: String
    /// ISO 3166 alpha-2 country code.
    public let country: String
    /// Subdivision code, for example NT for the Northwest Territories.
    public let region: String
    public let latitude: Double
    public let longitude: Double
    public let elevationFt: Int
    /// Longest open runway, in feet (0 for a water aerodrome).
    public let runwayFt: Int
    public let surface: RunwaySurface
    public let kind: AirportKind
    public let scheduled: Bool
    /// People who live within reach of this airport, shared out between neighbouring airports (see tools/data/populations.py).
    public let population: Int

    public var id: String { code }

    public func distanceKm(to other: Airport) -> Double {
        GeoMath.distanceKm(lat1: latitude, lon1: longitude, lat2: other.latitude, lon2: other.longitude)
    }

    /// The name without the word "Airport", for tight screens.
    public var shortName: String {
        var n = name
        for suffix in [" International Airport", " Airport", " Airfield", " Aerodrome"] where n.hasSuffix(suffix) {
            n = String(n.dropLast(suffix.count))
            break
        }
        return n.isEmpty ? name : n
    }
}

extension Airport {
    /// Parses one generated row: code|icao|name|city|country|region|lat|lon|elevation|runway|surface|kind|scheduled|population
    init?(row: Substring) {
        let f = row.split(separator: "|", omittingEmptySubsequences: false)
        guard f.count == 14,
              let lat = Double(f[6]), let lon = Double(f[7]), let elev = Int(f[8]), let rwy = Int(f[9]),
              let surface = RunwaySurface(rawValue: String(f[10])), let kind = AirportKind(rawValue: String(f[11])),
              let pop = Int(f[13]) else { return nil }
        self.init(code: String(f[0]), icao: String(f[1]), name: String(f[2]), city: String(f[3]), country: String(f[4]), region: String(f[5]),
                  latitude: lat, longitude: lon, elevationFt: elev, runwayFt: rwy, surface: surface, kind: kind,
                  scheduled: f[12] == "1", population: pop)
    }
}
