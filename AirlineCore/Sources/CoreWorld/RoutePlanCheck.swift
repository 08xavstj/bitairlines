// CoreWorld/RoutePlanCheck.swift: while the player plans a route on the map, can any aircraft they own fly it? If not, which
// stretch is the trouble, and is there an airport in between that would make it flyable. Codes and numbers only.
import CoreCatalog

/// What the airline's own fleet makes of a planned list of stops.
public struct PlannerCheck: Sendable, Hashable {
    /// True if the airline owns any aircraft at all (bought, on order or being restored).
    public var hasAircraft: Bool
    /// Aircraft owned that could fly the whole route as planned, in fleet order.
    public var fittingAircraftIDs: [Int]
    /// The first leg none of them can fly: stops[blockedLeg] to the next stop (the last leg goes back to the first stop).
    public var blockedLeg: Int?
    /// Why that leg cannot be flown: out of range (with the km) or an airport none of them can use.
    public var blockedProblem: WorldError?
    /// An airport to insert after stops[blockedLeg] so one of the aircraft can fly that stretch in two hops.
    public var suggestedStop: String?
    /// Every leg can be flown by some aircraft, but no single aircraft fits the whole route: the first aircraft's reason.
    public var fleetProblem: WorldError?

    public var fits: Bool { !fittingAircraftIDs.isEmpty }
}

extension World {
    /// A route through the stops with only the distances filled in, for asking whether an aircraft could fly it (nil if a stop is unknown).
    public func probeRoute(stops: [String]) -> Route? {
        guard stops.count >= 2 else { return nil }
        var legs: [LegState] = []
        for (k, code) in stops.enumerated() {
            guard let a = AirportCatalog.airport(code), let b = AirportCatalog.airport(stops[(k + 1) % stops.count]) else { return nil }
            legs.append(LegState(from: a.code, to: b.code, distanceKm: a.distanceKm(to: b), marketPaxPerDay: 0, marketCargoKgPerDay: 0, marketFare: 0,
                                 waitingPax: 0, waitingCargoKg: 0, lastUpdate: 0, maturity: 0, passengersCarried: 0, revenue: 0,
                                 departuresThisWeek: 0, departuresLastWeek: 0, nextSlot: 0))
        }
        return Route(id: 0, name: "", stops: stops, fareMultiplier: 1, carriesCargo: true, frequency: 1, autoFrequency: false, legs: legs, aircraftIDs: [],
                     openedDay: 0, flights: 0, revenueThisMonth: 0, costThisMonth: 0, revenueLastMonth: 0, costLastMonth: 0)
    }

    /// Weighs a planned route against the fleet the airline owns.
    public func plannerCheck(stops: [String]) -> PlannerCheck {
        let planes = aircraft.filter { $0.type != nil }
        var check = PlannerCheck(hasAircraft: !planes.isEmpty, fittingAircraftIDs: [], blockedLeg: nil, blockedProblem: nil, suggestedStop: nil, fleetProblem: nil)
        guard !planes.isEmpty, let route = probeRoute(stops: stops) else { return check }
        for plane in planes {
            if let type = plane.type, fitProblem(type: type, route: route, kits: plane.kits) == nil { check.fittingAircraftIDs.append(plane.id) }
        }
        if check.fits { return check }
        for (l, leg) in route.legs.enumerated() {
            guard let a = AirportCatalog.airport(leg.from), let b = AirportCatalog.airport(leg.to) else { continue }
            if planes.contains(where: { canFlyLeg($0, from: a, to: b) }) { continue }
            check.blockedLeg = l
            check.blockedProblem = legProblem(planes, from: a, to: b)
            if case .some(.outOfRange) = check.blockedProblem, stops.count < World.maxStops {
                check.suggestedStop = stopBetween(a, b, planes: planes, avoiding: stops)
            }
            return check
        }
        if let first = planes.first, let type = first.type { check.fleetProblem = fitProblem(type: type, route: route, kits: first.kits) }
        return check
    }

    /// True if any aircraft the airline owns can use both airports and fly from one to the other in one go.
    public func fleetCanFly(from: String, to: String) -> Bool {
        guard let a = AirportCatalog.airport(from), let b = AirportCatalog.airport(to) else { return false }
        return aircraft.contains { canFlyLeg($0, from: a, to: b) }
    }

    /// True if this aircraft can use both airports (in some season) and fly between them in one go.
    func canFlyLeg(_ plane: Aircraft, from a: Airport, to b: Airport) -> Bool {
        guard let type = plane.type else { return false }
        let cap = Capability(type: type, kits: plane.kits)
        return canUse(cap, at: a) && canUse(cap, at: b) && type.canFly(km: a.distanceKm(to: b))
    }

    /// Why no aircraft in the list can fly from `a` to `b`: too far if one of them can use both airports, else an airport none can use.
    func legProblem(_ planes: [Aircraft], from a: Airport, to b: Airport) -> WorldError {
        let usesA = planes.contains { plane in plane.type.map { canUse(Capability(type: $0, kits: plane.kits), at: a) } ?? false }
        let usesB = planes.contains { plane in plane.type.map { canUse(Capability(type: $0, kits: plane.kits), at: b) } ?? false }
        let usesBoth = planes.contains { plane in
            plane.type.map { canUse(Capability(type: $0, kits: plane.kits), at: a) && canUse(Capability(type: $0, kits: plane.kits), at: b) } ?? false
        }
        if usesBoth { return .outOfRange(km: Int(a.distanceKm(to: b))) }
        if !usesA { return .aircraftCannotUse(airport: a.code) }
        if !usesB { return .aircraftCannotUse(airport: b.code) }
        return .aircraftCannotUse(airport: b.code)
    }

    /// The map airport that splits a too-long stretch into two hops one of the aircraft can fly, with the least extra distance:
    /// open to the airline (level and permit), usable by that aircraft, and selling fuel in Realism. Ties go to the lower code.
    func stopBetween(_ a: Airport, _ b: Airport, planes: [Aircraft], avoiding stops: [String]) -> String? {
        var best: (km: Double, code: String)?
        for c in FerryGrid.airports {
            if stops.contains(c.code) { continue }
            if c.code != airline.home && Progression.requiredLevel(for: c) > airline.level { continue }
            if !airline.permits.contains(c.country) { continue }
            if ops.mode.fuelOnlyWhereSold && !sellsFuel(c) { continue }
            let first = a.distanceKm(to: c)
            let second = c.distanceKm(to: b)
            let total = first + second
            if let best, total > best.km || (total == best.km && c.code > best.code) { continue }
            let works = planes.contains { plane in
                guard let type = plane.type else { return false }
                let cap = Capability(type: type, kits: plane.kits)
                return type.canFly(km: first) && type.canFly(km: second) && canUse(cap, at: a) && canUse(cap, at: b) && canUse(cap, at: c)
            }
            if works { best = (total, c.code) }
        }
        return best?.code
    }
}
