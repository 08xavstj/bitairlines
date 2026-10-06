// CoreWorld/FerryPlan.swift: getting an empty aircraft to an airport it cannot reach in one go.
// A shortest-path search over the map airports finds stops the aircraft can land at (and buy fuel at, in Realism), with every hop
// within its range. The aircraft flies the path one hop at a time: startFerry (Flights.swift) flies the first hop, and on landing
// its route, its job or its stored ferry target sends it on to the next one.
import CoreCatalog
import CoreSim

extension Tuning {
    /// Each landing on a positioning flight counts as this many extra km when the planner compares paths, so it does not add a
    /// stop only to save a few km.
    public static let ferryStopPenaltyKm = 150.0
}

/// An empty positioning flight split into hops. `hops` are the airports it lands at, in order; the last one is the destination.
/// Empty when the aircraft is already there.
public struct FerryPlan: Sendable, Hashable {
    public var from: String
    public var hops: [String]
    /// Total distance flown.
    public var km: Double
    /// Block hours of every hop, plus a turnaround at each stop on the way.
    public var hours: Double

    /// Landings before the destination.
    public var stopsOnTheWay: Int { max(0, hops.count - 1) }
    public var destination: String? { hops.last }
}

/// The map airports as points on a unit sphere, worked out once, in code order (so ties always break the same way).
enum FerryGrid {
    struct Point: Sendable {
        let x: Double
        let y: Double
        let z: Double
    }

    static let airports: [Airport] = AirportCatalog.all.sorted { $0.code < $1.code }
    static let points: [Point] = airports.map { point($0) }
    static let index: [String: Int] = {
        var map: [String: Int] = [:]
        for (k, airport) in airports.enumerated() { map[airport.code] = k }
        return map
    }()

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
}

extension World {
    /// Where the aircraft will next be on the ground: where it is landing if it is in the air, else where it is.
    public func nextGround(of plane: Aircraft) -> String { plane.flight?.to ?? plane.location }

    /// The empty flight that gets this aircraft from where it will next be on the ground to the first reachable of `goals`
    /// (nil if none can be reached, even with stops). Empty hops when it is already at one of them.
    public func ferryPlan(aircraftID: Int, toAny goals: [String]) -> FerryPlan? {
        guard let i = aircraftIndex(aircraftID) else { return nil }
        return ferryPlan(aircraftIndex: i, from: nextGround(of: aircraft[i]), toAny: goals)
    }

    /// The airports an empty flight from `from` to `to` lands at (the last is `to`), or nil if this aircraft cannot get there.
    public func ferryPath(from: String, to: String, aircraftIndex i: Int) -> [String]? {
        ferryPlan(aircraftIndex: i, from: from, toAny: [to])?.hops
    }

    /// The cheapest empty flight for aircraft `i` from `start` to the first reachable of `goals`, or nil if there is none.
    /// A goal it can reach in one hop is taken at once, in the order given, so a direct flight is never swapped for a detour.
    /// Otherwise a shortest-path search (A*, with the straight line to the nearest goal as the estimate) over the map airports the
    /// aircraft can use this month (in Realism only those that sell fuel), every hop within range. Each landing adds
    /// `Tuning.ferryStopPenaltyKm`; equal paths go to the lower airport code. A goal must be usable by the aircraft in some season.
    func ferryPlan(aircraftIndex i: Int, from start: String, toAny goals: [String]) -> FerryPlan? {
        guard aircraft.indices.contains(i), let type = aircraft[i].type, let here = AirportCatalog.airport(start) else { return nil }
        if goals.contains(start) { return FerryPlan(from: start, hops: [], km: 0, hours: 0) }
        let cap = Capability(type: type, kits: aircraft[i].kits)
        let targets = goals.compactMap { AirportCatalog.airport($0) }.filter { canUse(cap, at: $0) }
        guard !targets.isEmpty else { return nil }
        for target in targets where type.canFly(km: here.distanceKm(to: target)) {
            return makeFerryPlan(type: type, from: here, hops: [target.code])
        }
        guard let hops = searchFerry(type: type, cap: cap, from: here, targets: targets) else { return nil }
        return makeFerryPlan(type: type, from: here, hops: hops)
    }

    /// Distance and hours of a path, checked hop by hop with the same distance the flight uses. Nil if a hop is out of range.
    func makeFerryPlan(type: AircraftType, from here: Airport, hops: [String]) -> FerryPlan? {
        var km = 0.0
        var hours = 0.0
        var last = here
        for code in hops {
            guard let next = AirportCatalog.airport(code) else { return nil }
            let d = last.distanceKm(to: next)
            guard type.canFly(km: d) else { return nil }
            km += d
            hours += type.blockHours(km: d)
            last = next
        }
        hours += turnaroundHours(type.engine) * Double(max(0, hops.count - 1))
        return FerryPlan(from: here.code, hops: hops, km: km, hours: hours)
    }

    /// The search behind `ferryPlan`: the airport codes landed at, or nil. Neighbours are found on demand by scanning the grid
    /// (a cheap chord test first), so nothing is built ahead and a search touches only the airports it needs.
    private func searchFerry(type: AircraftType, cap: Capability, from here: Airport, targets: [Airport]) -> [String]? {
        let grid = FerryGrid.airports
        let points = FerryGrid.points
        let n = grid.count
        let month = clock.date.month
        let fuelRule = ops.mode.fuelOnlyWhereSold
        var isGoal = [Bool](repeating: false, count: n)
        var goalPoints: [FerryGrid.Point] = []
        for target in targets {
            guard let k = FerryGrid.index[target.code] else { continue }
            isGoal[k] = true
            goalPoints.append(points[k])
        }
        // A retired airport is not on the grid: it can only be reached directly (handled by the caller).
        guard !goalPoints.isEmpty else { return nil }

        // Stops on the way: usable this month and, in Realism, selling fuel. A goal needs neither (it was checked by the caller).
        var usable = [Bool](repeating: false, count: n)
        for k in 0..<n {
            usable[k] = isGoal[k] || (canUse(cap, at: grid[k], month: month) && (!fuelRule || sellsFuel(grid[k])))
        }

        // Hops are at most the range, less half a km so the flight's own distance check always agrees.
        let reach = Double(type.rangeKm) - 0.5
        let halfAngle = min(1.5707963267948966, reach / (2.0 * GeoMath.earthRadiusKm))
        let maxChord = 2.0 * GeoMath.sine(halfAngle) + 1e-9
        let maxChord2 = maxChord * maxChord
        let radius = GeoMath.earthRadiusKm

        var cost = [Double](repeating: Double.infinity, count: n)
        var parent = [Int](repeating: -1, count: n)
        var closed = [Bool](repeating: false, count: n)
        var estimate = [Double](repeating: -1, count: n)
        var open: [Int] = []
        if let s = FerryGrid.index[here.code] { closed[s] = true }

        var point = FerryGrid.point(here)
        var base = 0.0
        var current = -1
        while true {
            // Relax every usable airport within one hop of the current one.
            for k in 0..<n where usable[k] && !closed[k] {
                let c2 = FerryGrid.chord2(point, points[k])
                if c2 > maxChord2 { continue }
                let km = FerryGrid.km(chord2: c2)
                if km > reach { continue }
                let total = base + km + Tuning.ferryStopPenaltyKm
                if total < cost[k] {
                    if cost[k] == Double.infinity { open.append(k) }
                    cost[k] = total
                    parent[k] = current
                }
            }
            // Take the open airport with the lowest cost plus estimate; ties go to the lower code (the grid is in code order).
            guard !open.isEmpty else { return nil }
            var bestSlot = 0
            var bestScore = Double.infinity
            for slot in open.indices {
                let k = open[slot]
                if estimate[k] < 0 {
                    var nearest = Double.infinity
                    for goal in goalPoints { nearest = min(nearest, FerryGrid.chord2(points[k], goal)) }
                    estimate[k] = radius * nearest.squareRoot()
                }
                let score = cost[k] + estimate[k]
                if score < bestScore || (score == bestScore && k < open[bestSlot]) {
                    bestSlot = slot
                    bestScore = score
                }
            }
            let k = open[bestSlot]
            open.swapAt(bestSlot, open.count - 1)
            open.removeLast()
            closed[k] = true
            if isGoal[k] {
                var hops: [String] = []
                var step = k
                while step >= 0 {
                    hops.append(grid[step].code)
                    step = parent[step]
                }
                return Array(hops.reversed())
            }
            point = points[k]
            base = cost[k]
            current = k
        }
    }

    /// Why this aircraft cannot get (empty) to any of `goals` from where it will next be on the ground, or nil if it can.
    func positioningProblem(aircraftIndex i: Int, toAny goals: [String]) -> WorldError? {
        let start = nextGround(of: aircraft[i])
        if goals.contains(start) || ferryPlan(aircraftIndex: i, from: start, toAny: goals) != nil { return nil }
        guard let a = AirportCatalog.airport(start), let first = goals.first, let b = AirportCatalog.airport(first) else { return .outOfRange(km: 0) }
        return .outOfRange(km: Int(a.distanceKm(to: b)))
    }
}
