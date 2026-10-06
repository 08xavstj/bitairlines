// CoreCatalog/AircraftType.swift: one aircraft model (static data). Figures are rounded real-world values tuned for game balance, not manuals.
import CoreSim

public enum EngineKind: String, Sendable, Hashable, Codable {
    case piston = "P", turboprop = "T", jet = "J"
}

/// Which hand-drawn side-view sprite shape an aircraft uses (the app maps these to pixel art).
public enum SpriteFamily: String, Sendable, Hashable, Codable, CaseIterable {
    case lightSingle = "LS", utilitySingle = "HS", floatSingle = "FS", twinTurboprop = "TT", floatTwin = "FT"
    case taildragger = "TD", commuter = "CT", regionalTurboprop = "RT", regionalJet = "RJ", rearEngineMainline = "MD"
    case narrowbody = "NB", widebody = "WB", jumbo = "JB", superJumbo = "SB"
}

public struct AircraftType: Sendable, Hashable, Identifiable {
    /// Stable id used in saves, for example "dhc6".
    public let id: String
    public let manufacturer: String
    public let name: String
    public let family: SpriteFamily
    public let engine: EngineKind
    /// Passenger seats in the game's single-class layout.
    public let seats: Int
    /// Cargo hold capacity in kilograms (bush types carry freight in the cabin).
    public let cargoKg: Int
    public let rangeKm: Int
    public let cruiseKph: Int
    public let fuelBurnKgPerHour: Int
    /// Runway length needed to take off and land at a typical weight.
    public let runwayFt: Int
    public let paved: Bool
    public let gravel: Bool
    public let water: Bool
    /// New price in US dollars (for types out of production, the reference value that used prices are scaled from).
    public let priceUSD: Int
    public let maxTakeoffKg: Int
    public let maintenanceUSDPerHour: Int
    public let pilots: Int
    /// The airline certificate level that unlocks this type (1 bush up to 7 jumbo).
    public let level: Int
    public let lengthM: Double
    public let wingspanM: Double
    public let inProduction: Bool

    public var cabinCrew: Int { seats <= 19 ? 0 : (seats + 49) / 50 }
    public var crew: Int { pilots + cabinCrew }
    public var displayName: String { "\(manufacturer) \(name)" }

    public func canLand(at airport: Airport) -> Bool {
        switch airport.surface {
        case .water: return water
        case .paved: return (paved || gravel) && airport.runwayFt >= runwayFt
        case .gravel: return gravel && airport.runwayFt >= runwayFt
        }
    }

    public func canFly(km: Double) -> Bool { km <= Double(rangeKm) }

    /// Gate to gate time in hours for a leg: a fixed allowance for taxi, climb and approach, then cruise.
    public func blockHours(km: Double) -> Double {
        let allowance = engine == .jet ? 0.45 : 0.30
        return allowance + km / Double(cruiseKph)
    }
}

extension AircraftType {
    /// Parses one row of AircraftRows (20 pipe-separated fields).
    init?(row: Substring) {
        let f = row.split(separator: "|", omittingEmptySubsequences: false)
        guard f.count == 20,
              let family = SpriteFamily(rawValue: String(f[3])), let engine = EngineKind(rawValue: String(f[4])),
              let seats = Int(f[5]), let cargo = Int(f[6]), let range = Int(f[7]), let cruise = Int(f[8]), let burn = Int(f[9]),
              let runway = Int(f[10]), let priceK = Int(f[12]), let mtow = Int(f[13]), let maint = Int(f[14]),
              let pilots = Int(f[15]), let level = Int(f[16]), let length = Double(f[17]), let wing = Double(f[18]) else { return nil }
        let ops = f[11]
        self.init(id: String(f[0]), manufacturer: String(f[1]), name: String(f[2]), family: family, engine: engine,
                  seats: seats, cargoKg: cargo, rangeKm: range, cruiseKph: cruise, fuelBurnKgPerHour: burn, runwayFt: runway,
                  paved: ops.contains("P"), gravel: ops.contains("G"), water: ops.contains("W"),
                  priceUSD: priceK * 1000, maxTakeoffKg: mtow, maintenanceUSDPerHour: maint, pilots: pilots, level: level,
                  lengthM: length, wingspanM: wing, inProduction: f[19] == "1")
    }
}
