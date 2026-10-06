// CoreWorld/FerryGrid.swift: the map airports as points on a sphere, and each airport's neighbours, for the empty-flight planner
// (FerryPlan.swift). Everything here depends only on the airport catalog, so it is worked out once and shared.
import CoreCatalog
import CoreSim

/// The map airports as points on a unit sphere, worked out once, in code order (so ties always break the same way).
enum FerryGrid {
    struct Point: Sendable {
        let x: Double
        let y: Double
        let z: Double
    }

    static let airports: [Airport] = AirportCatalog.all.sorted { $0.code < $1.code }
    static let points: [Point] = FerryGrid.airports.map { FerryGrid.point($0) }
    static let index: [String: Int] = {
        var map: [String: Int] = [:]
        for (k, airport) in FerryGrid.airports.enumerated() { map[airport.code] = k }
        return map
    }()

    /// 0, 1, 2 ... for a search that looks at every airport.
    static let everyIndex: [Int] = Array(0..<FerryGrid.airports.count)

    /// The neighbour lists hold hops up to this long. An aircraft with a longer range scans every airport (it rarely needs a stop).
    static let tableKm = 3_000.0
    static let tableChord2: Double = FerryGrid.maxChord2(reachKm: FerryGrid.tableKm)

    /// For each airport, every other airport within `tableKm`, nearest first (equal distances in code order). A search reads a
    /// list only as far as its own reach, so each step looks at a few dozen airports instead of all of them.
    static let neighbours: [[Int]] = {
        let all = FerryGrid.points
        let limit = FerryGrid.tableChord2
        var lists = [[Int]](repeating: [], count: all.count)
        for i in all.indices {
            var near: [(c2: Double, k: Int)] = []
            for k in all.indices where k != i {
                let c2 = FerryGrid.chord2(all[i], all[k])
                if c2 <= limit { near.append((c2: c2, k: k)) }
            }
            near.sort { $0.c2 != $1.c2 ? $0.c2 < $1.c2 : $0.k < $1.k }
            lists[i] = near.map { $0.k }
        }
        return lists
    }()

    /// How many airports the island check (FerryPlan.swift, `goalsCutOff`) visits before it gives up and lets the full search run.
    static let islandLimit = 64

    static func point(_ a: Airport) -> Point {
        let rad = 3.141592653589793 / 180.0
        let lat = a.latitude * rad
        let lon = a.longitude * rad
        let c = GeoMath.cosine(lat)
        return Point(x: c * GeoMath.cosine(lon), y: c * GeoMath.sine(lon), z: GeoMath.sine(lat))
    }

    /// Squared straight-line (chord) distance between two points on the unit sphere.
    static func chord2(_ a: Point, _ b: Point) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        let dz = a.z - b.z
        return dx * dx + dy * dy + dz * dz
    }

    /// Great-circle km for a chord. Short chords use the series 2 asin(c/2) = c + c^3/24 + 3c^5/640 + 5c^7/7168 (within metres),
    /// long ones the exact arc sine. Never less than the chord itself, so the straight-line estimate stays a lower bound.
    static func km(chord2 c2: Double) -> Double {
        let c = c2.squareRoot()
        if c <= 0.6 {
            let c3 = c * c2
            return GeoMath.earthRadiusKm * (c + c3 / 24.0 + 3.0 * c3 * c2 / 640.0 + 5.0 * c3 * c2 * c2 / 7168.0)
        }
        return GeoMath.earthRadiusKm * 2.0 * GeoMath.arcSine(c / 2.0)
    }

    /// The squared chord of the longest hop for a reach in km, with a hair of slack so rounding never drops a hop that fits.
    static func maxChord2(reachKm: Double) -> Double {
        let halfAngle = min(1.5707963267948966, reachKm / (2.0 * GeoMath.earthRadiusKm))
        let maxChord = 2.0 * GeoMath.sine(halfAngle) + 1e-9
        return maxChord * maxChord
    }
}
