// CoreWorld/Positioning.swift: where an aircraft flying empty heads for, and what happens when it can never get there.
// It heads for the nearest airport of its work it can use this month. When it can never get there (no chain of stops reaches
// it, or it cannot take off where it is), it gives up: it stays where it is and the news says why. The flight itself is
// startFerry in Flights.swift (through the same take-off gate as every flight); the path through stops is in FerryPlan.swift.
import CoreCatalog

/// Why an aircraft gave up flying empty to its route or to where it was sent. News: `.milestone`, subject
/// "ferrygone:<registration>:<airport where it stays>", amount the raw value.
public enum FerryGiveUpReason: Int, Sendable, Hashable, CaseIterable {
    /// No chain of stops it can fly this month reaches any airport it was heading for.
    case noWayThere = 0
    /// It cannot take off where it is in any season (floats fitted at an airport with only a runway, for example).
    case cannotLeave = 1
}

extension World {
    /// The empty flight startFerry flies from `start` to one of `goals`. Goals the aircraft can use this month come first, the
    /// nearest first (ties keep the order given), so a wheel-ski aircraft does not land on an open lake in summer and a route
    /// listed far stop first is joined at its near stop. A goal in range is flown to directly. Only when none of the goals usable
    /// this month can be reached does it head for one it cannot use yet; the last hop then waits at the gate for the season.
    /// Nil when no goal can be reached at all.
    func positioningPlan(aircraftIndex i: Int, from start: String, toAny goals: [String]) -> FerryPlan? {
        guard aircraft.indices.contains(i), let type = aircraft[i].type, let here = AirportCatalog.airport(start) else { return nil }
        let cap = Capability(type: type, kits: aircraft[i].kits)
        let month = clock.date.month
        var ranked: [(later: Int, km: Double, order: Int, code: String)] = []
        for (order, code) in goals.enumerated() {
            guard let airport = AirportCatalog.airport(code) else { continue }
            let later = canUse(cap, at: airport, month: month) ? 0 : 1
            ranked.append((later: later, km: here.distanceKm(to: airport), order: order, code: code))
        }
        ranked.sort { ($0.later, $0.km, $0.order) < ($1.later, $1.km, $1.order) }
        let all = ranked.map { $0.code }
        let usableNow = ranked.filter { $0.later == 0 }.map { $0.code }
        if !usableNow.isEmpty && usableNow.count < all.count, let plan = ferryPlan(aircraftIndex: i, from: start, toAny: usableNow) {
            return plan
        }
        return ferryPlan(aircraftIndex: i, from: start, toAny: all)
    }

    /// The aircraft can never get to where it was flying empty: the news says so and why. The caller parks it, or takes it off
    /// the route it could not reach.
    mutating func noteFerryGivenUp(_ i: Int) {
        var reason = FerryGiveUpReason.noWayThere
        if let type = aircraft[i].type, let here = AirportCatalog.airport(aircraft[i].location),
           !canUse(Capability(type: type, kits: aircraft[i].kits), at: here) {
            reason = .cannotLeave
        }
        addNews(.milestone, subject: "ferrygone:\(aircraft[i].registration):\(aircraft[i].location)", amount: reason.rawValue)
    }
}
