// CoreWorld/SharedAircraft.swift: one aircraft flying up to three routes.
//   The aircraft's `routeID` is the route it flies now; `otherRouteIDs` are the routes it also flies.
//   The aircraft is listed in the `aircraftIDs` of every one of them.
//   At each stop it takes the route whose next departure from there comes first, so a thin route's quiet days are filled by another.
import CoreCatalog

extension Aircraft {
    /// The routes it also flies, besides the current one. Missing from older saves.
    public var otherRouteIDs: [Int] {
        get { otherRoutesStore ?? [] }
        set { otherRoutesStore = newValue.isEmpty ? nil : newValue }
    }

    /// Every route it flies: the current one first.
    public var allRouteIDs: [Int] {
        guard let current = routeID else { return [] }
        return [current] + otherRouteIDs
    }

    /// The part of this aircraft one of its routes can count on (1 for an aircraft on a single route).
    public var routeShare: Double { 1.0 / Double(max(1, allRouteIDs.count)) }
}

extension World {
    /// Most routes one aircraft can fly. A rule of the game, not a balance number.
    public static let maxRoutesPerAircraft = 3

    // MARK: Questions the app asks

    /// The routes this aircraft could also fly: they share an airport with one of its routes and it does not fly them yet.
    public func routesToShare(aircraftID: Int) -> [Route] {
        guard let plane = aircraft.first(where: { $0.id == aircraftID }), plane.routeID != nil else { return [] }
        let flown = plane.allRouteIDs
        return routes.filter { !flown.contains($0.id) && meets($0, flown) }
    }

    /// Why the aircraft cannot also fly this route (nil if it can).
    public func addRouteProblem(aircraftID: Int, routeID: Int) -> WorldError? {
        guard let plane = aircraft.first(where: { $0.id == aircraftID }) else { return .unknownAircraft(aircraftID) }
        guard let r = routeIndex(routeID) else { return .unknownRoute(routeID) }
        guard let type = plane.type else { return .unknownType(plane.typeID) }
        guard plane.isDelivered else { return .notDelivered }
        if case .grounded = plane.status { return .aircraftBusy }
        if plane.jobID != nil || plane.awaitingRestoration { return .aircraftBusy }
        guard plane.routeID != nil else { return .invalidChoice }
        let flown = plane.allRouteIDs
        if flown.contains(routeID) { return .invalidChoice }
        if flown.count >= World.maxRoutesPerAircraft { return .tooManyRoutes }
        if let problem = fitProblem(type: type, route: routes[r], kits: plane.kits) { return problem }
        if !meets(routes[r], flown) { return .routesDoNotMeet }
        return nil
    }

    /// True if the route shares an airport with one of the routes in the list.
    func meets(_ route: Route, _ routeIDs: [Int]) -> Bool {
        for rid in routeIDs {
            guard let r = routeIndex(rid) else { continue }
            if routes[r].stops.contains(where: { route.stops.contains($0) }) { return true }
        }
        return false
    }

    /// How many aircraft a route can count on: a shared aircraft counts as one over the number of routes it flies.
    public func aircraftShare(onRoute routeID: Int) -> Double {
        guard let r = routeIndex(routeID) else { return 0 }
        var total = 0.0
        for id in routes[r].aircraftIDs {
            if let plane = aircraft.first(where: { $0.id == id }) { total += plane.routeShare }
        }
        return total
    }

    /// The suggested schedule when the route's aircraft may be shared with other routes (`aircraftShare` may be a fraction).
    public func suggestedFrequency(route: Route, type: AircraftType, aircraftShare: Double) -> Double {
        let share = max(aircraftShare, 1.0 / Double(World.maxRoutesPerAircraft))
        let target = min(demandFrequency(route: route, type: type), share * cyclesPerAircraftPerDay(route: route, type: type))
        return Route.snapFrequency(target)
    }

    // MARK: Player actions

    /// Lets an aircraft that already flies a route also fly this one. It keeps its current route.
    public mutating func addRoute(aircraftID: Int, routeID: Int) throws {
        if let problem = addRouteProblem(aircraftID: aircraftID, routeID: routeID) { throw problem }
        guard let i = aircraftIndex(aircraftID), let r = routeIndex(routeID) else { throw WorldError.unknownAircraft(aircraftID) }
        aircraft[i].otherRouteIDs = aircraft[i].otherRouteIDs + [routeID]
        routes[r].aircraftIDs.append(aircraftID)
        // Look again now: the new route may have a departure sooner than the one it is waiting for.
        if case .boarding = aircraft[i].status { aircraft[i].status = .boarding(until: clock.minute) }
        refreshAutoFrequency(routeIDs: aircraft[i].allRouteIDs)
    }

    /// Stops an aircraft flying one of its routes. If that was the current one, another of its routes takes over.
    public mutating func removeRoute(aircraftID: Int, routeID: Int) throws {
        guard let i = aircraftIndex(aircraftID) else { throw WorldError.unknownAircraft(aircraftID) }
        guard aircraft[i].allRouteIDs.contains(routeID) else { throw WorldError.invalidChoice }
        let before = aircraft[i].allRouteIDs
        detach(i, fromRoute: routeID)
        refreshAutoFrequency(routeIDs: before)
    }

    // MARK: Keeping the lists consistent

    /// Takes the aircraft off every route it flies. The caller decides what happens to its status.
    mutating func detachFromAllRoutes(_ i: Int) {
        let id = aircraft[i].id
        for rid in aircraft[i].allRouteIDs {
            if let r = routeIndex(rid) { routes[r].aircraftIDs.removeAll { $0 == id } }
        }
        aircraft[i].routeID = nil
        aircraft[i].otherRouteIDs = []
        aircraft[i].ferryTargetStore = nil
    }

    /// Takes the aircraft off one route. If it was the current route, the next of its other routes becomes current.
    /// An aircraft waiting at the gate looks again (or parks, if it has no route left).
    mutating func detach(_ i: Int, fromRoute routeID: Int) {
        let id = aircraft[i].id
        if let r = routeIndex(routeID) { routes[r].aircraftIDs.removeAll { $0 == id } }
        var others = aircraft[i].otherRouteIDs.filter { $0 != routeID }
        if aircraft[i].routeID == routeID {
            let next: Int? = others.isEmpty ? nil : others.removeFirst()
            aircraft[i].routeID = next
            aircraft[i].otherRouteIDs = others
            if case .boarding = aircraft[i].status { aircraft[i].status = next == nil ? .idle : .boarding(until: clock.minute) }
        } else {
            aircraft[i].otherRouteIDs = others
        }
    }

    /// Re-picks the schedule of routes still on automatic scheduling, counting shared aircraft as a part.
    mutating func refreshAutoFrequency(routeIDs: [Int]) {
        for rid in routeIDs {
            guard let r = routeIndex(rid), routes[r].autoFrequency else { continue }
            let first = routes[r].aircraftIDs.first
            guard let planeID = first, let type = aircraft.first(where: { $0.id == planeID })?.type else { continue }
            let share = aircraftShare(onRoute: rid)
            routes[r].frequency = suggestedFrequency(route: routes[r], type: type, aircraftShare: share)
        }
    }

    // MARK: Picking the route at a stop

    /// Before departing: of the aircraft's routes with a leg from where it is, take the one whose next departure comes first.
    /// Routes it cannot fly right now (weather, a frozen lake, no longer fits) come last. Ties keep the current route, then the lower id.
    /// If none of its routes has a leg from here, nothing changes (it ferries to its current route).
    mutating func pickSharedRoute(_ i: Int) {
        let others = aircraft[i].otherRouteIDs
        guard let current = aircraft[i].routeID, !others.isEmpty, let type = aircraft[i].type else { return }
        let here = aircraft[i].location
        let kits = aircraft[i].kits
        let cap = Capability(type: type, kits: kits)
        let month = clock.date.month
        var best: (Int, Int, Int, Int)?
        for rid in [current] + others {
            guard let r = routeIndex(rid), let l = routes[r].firstLeg(from: here) else { continue }
            let leg = routes[r].legs[l]
            var blocked = 1
            if closureEnd(of: leg.from) == nil && closureEnd(of: leg.to) == nil,
               let a = AirportCatalog.airport(leg.from), let b = AirportCatalog.airport(leg.to),
               canUse(cap, at: a, month: month), canUse(cap, at: b, month: month),
               fitProblem(type: type, route: routes[r], kits: kits) == nil {
                blocked = 0
            }
            // A slot already passed counts as now, so two routes that could both leave now keep the current one.
            let slot = max(leg.nextSlot, clock.minute)
            let key = (blocked, slot, rid == current ? 0 : 1, rid)
            if let previous = best, !(key < previous) { continue }
            best = key
        }
        guard let chosen = best?.3, chosen != current else { return }
        aircraft[i].otherRouteIDs = others.map { $0 == chosen ? current : $0 }
        aircraft[i].routeID = chosen
    }
}
