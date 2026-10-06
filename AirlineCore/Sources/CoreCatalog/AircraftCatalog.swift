// CoreCatalog/AircraftCatalog.swift: every aircraft model, parsed once from AircraftRows.

public enum AircraftCatalog {
    public static let all: [AircraftType] = AircraftRows.rows.split(separator: "\n").compactMap { AircraftType(row: $0) }

    public static let byID: [String: AircraftType] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func type(_ id: String) -> AircraftType? { byID[id] }

    /// Models an airline of this certificate level may operate, smallest first.
    public static func available(atLevel level: Int) -> [AircraftType] {
        all.filter { $0.level <= level }
    }

    /// The types that could serve a leg: able to use both airports and fly the distance.
    public static func suitable(from a: Airport, to b: Airport, km: Double) -> [AircraftType] {
        all.filter { $0.canLand(at: a) && $0.canLand(at: b) && $0.canFly(km: km) }
    }
}
