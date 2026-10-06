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
    /// `fast: false` runs the plain search over every airport; tests use it to check the quick one gives the same plans.
    func ferryPlan(aircraftIndex i: Int, from start: String, toAny goals: [String], fast: Bool = true) -> FerryPlan? {
        guard aircraft.indices.contains(i), let type = aircraft[i].type, let here = AirportCatalog.airport(start) else { return nil }
        if goals.contains(start) { return FerryPlan(from: start, hops: [], km: 0, hours: 0) }
        let cap = Capability(type: type, kits: aircraft[i].kits)
        let targets = goals.compactMap { AirportCatalog.airport($0) }.filter { canUse(cap, at: $0) }
        guard !targets.isEmpty else { return nil }
        for target in targets where type.canFly(km: here.distanceKm(to: target)) {
            return makeFerryPlan(type: type, from: here, hops: [target.code])
        }
        guard let hops = searchFerry(type: type, cap: cap, from: here, targets: targets, fast: fast) else { return nil }
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

    /// The search behind `ferryPlan`: the airport codes landed at, or nil.
    /// Quick paths (with `fast`): an aircraft with a range up to `FerryGrid.tableKm` reads each airport's neighbour list instead of
    /// scanning every airport, and a goal on an island the aircraft cannot reach is answered by `goalsCutOff` without searching
    /// the map. Both give exactly the plan of the plain scan: the airport taken next is always the open one with the lowest
    /// score (ties to the lower code), whatever order the neighbours were looked at in.
    private func searchFerry(type: AircraftType, cap: Capability, from here: Airport, targets: [Airport], fast: Bool) -> [String]? {
        let grid = FerryGrid.airports
        let points = FerryGrid.points
        let n = grid.count
        let month = clock.date.month
        let fuelRule = ops.mode.fuelOnlyWhereSold
        var isGoal = [Bool](repeating: false, count: n)
        var goals: [Int] = []
        var goalPoints: [FerryGrid.Point] = []
        for target in targets {
            guard let k = FerryGrid.index[target.code] else { continue }
            isGoal[k] = true
            goals.append(k)
            goalPoints.append(points[k])
        }
        // A retired airport is not on the grid: it can only be reached directly (handled by the caller).
        guard !goalPoints.isEmpty else { return nil }

        // Stops on the way: usable this month and, in Realism, selling fuel. A goal needs neither (it was checked by the caller).
        // Each airport is checked the first time the search meets it (0 not checked yet, 1 usable, 2 not), so a short search
        // checks only a few.
        var stopState = [UInt8](repeating: 0, count: n)
        func isStop(_ k: Int) -> Bool {
            if stopState[k] == 0 {
                let usable = isGoal[k] || (canUse(cap, at: grid[k], month: month) && (!fuelRule || sellsFuel(grid[k])))
                stopState[k] = usable ? 1 : 2
            }
            return stopState[k] == 1
        }

        // Hops are at most the range, less half a km so the flight's own distance check always agrees.
        let reach = Double(type.rangeKm) - 0.5
        let maxChord2 = FerryGrid.maxChord2(reachKm: reach)
        let radius = GeoMath.earthRadiusKm
        let useTable = fast && maxChord2 <= FerryGrid.tableChord2
        let startPoint = FerryGrid.point(here)
        let startIndex = FerryGrid.index[here.code]
        if useTable && goalsCutOff(goals: goals, startPoint: startPoint, maxChord2: maxChord2, isStop: isStop) { return nil }

        var cost = [Double](repeating: Double.infinity, count: n)
        var parent = [Int](repeating: -1, count: n)
        var closed = [Bool](repeating: false, count: n)
        var estimate = [Double](repeating: -1, count: n)
        var open: [Int] = []
        if let s = startIndex { closed[s] = true }

        var point = startPoint
        var base = 0.0
        var current = -1
        while true {
            // Relax every usable airport within one hop of the current one. From a neighbour list (nearest first) the first one
            // out of reach ends the list; the plain scan looks at every airport.
            let from: Int? = current >= 0 ? current : startIndex
            let listed: Int? = useTable ? from : nil
            let near: [Int] = listed.map { FerryGrid.neighbours[$0] } ?? FerryGrid.everyIndex
            for k in near {
                let c2 = FerryGrid.chord2(point, points[k])
                if c2 > maxChord2 {
                    if listed != nil { break }
                    continue
                }
                if closed[k] || !isStop(k) { continue }
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

    /// True when no chain of stops can join the goals to the start, found without searching the map: spreading out from the goals
    /// over the stops this aircraft can use runs out before it comes within one hop of the start. That is the usual answer for an
    /// island strip across open water. It gives up (false, so the full search runs) after `FerryGrid.islandLimit` airports.
    /// A hop is judged on the chord alone, which is a little generous, so a goal that can be reached is never called cut off.
    /// Needs the neighbour lists, so only for a reach within `FerryGrid.tableKm`.
    private func goalsCutOff(goals: [Int], startPoint: FerryGrid.Point, maxChord2: Double, isStop: (Int) -> Bool) -> Bool {
        let points = FerryGrid.points
        var seen = [Bool](repeating: false, count: points.count)
        var stack: [Int] = []
        for g in goals where !seen[g] {
            seen[g] = true
            stack.append(g)
        }
        var count = stack.count
        while let u = stack.popLast() {
            if FerryGrid.chord2(points[u], startPoint) <= maxChord2 { return false }
            for k in FerryGrid.neighbours[u] {
                if FerryGrid.chord2(points[u], points[k]) > maxChord2 { break }
                if seen[k] || !isStop(k) { continue }
                seen[k] = true
                count += 1
                if count > FerryGrid.islandLimit { return false }
                stack.append(k)
            }
        }
        return true
    }

    /// The empty flight that gets aircraft `i` from where it will next be on the ground to the first reachable of `goals`, and why
    /// not when there is none. One search answers both: the problem is nil when it can get there (the plan has no hops when it is
    /// there already).
    func positioning(aircraftIndex i: Int, toAny goals: [String]) -> (plan: FerryPlan?, problem: WorldError?) {
        let start = nextGround(of: aircraft[i])
        let plan = ferryPlan(aircraftIndex: i, from: start, toAny: goals)
        if goals.contains(start) || plan != nil { return (plan, nil) }
        guard let a = AirportCatalog.airport(start), let first = goals.first, let b = AirportCatalog.airport(first) else { return (nil, .outOfRange(km: 0)) }
        return (nil, .outOfRange(km: Int(a.distanceKm(to: b))))
    }

    /// Why this aircraft cannot get (empty) to any of `goals` from where it will next be on the ground, or nil if it can.
    func positioningProblem(aircraftIndex i: Int, toAny goals: [String]) -> WorldError? {
        if goals.contains(nextGround(of: aircraft[i])) { return nil }
        return positioning(aircraftIndex: i, toAny: goals).problem
    }
}
