// CoreWorld/FleetBalance.swift: spare aircraft. A route with more aircraft than its schedule needs lets the extra ones go to a
// route where they earn more. The route they leave keeps as many as it needs, so it is flown as before. The player can do it
// for one route ("Move spare aircraft"); the fleet planner does it for every route each Monday.
import CoreCatalog

/// One aircraft moved off a route that had more than it needed.
public struct SpareMove: Sendable, Hashable {
    public var aircraftID: Int
    public var fromRouteID: Int
    public var toRouteID: Int
    /// Forecast profit a day the move adds on the new route.
    public var gainPerDay: Int
}

extension World {
    /// Aircraft the route's schedule needs: the suggested schedule (or the player's own, when they set one) divided by the
    /// rotations one aircraft flies a day. Nil for a route with no aircraft.
    public func aircraftNeeded(routeID: Int) -> Int? {
        guard let r = routeIndex(routeID), let type = routeType(routes[r]) else { return nil }
        let route = routes[r]
        let cycles = cyclesPerAircraftPerDay(route: route, type: type)
        guard cycles > 0 else { return nil }
        let frequency = route.autoFrequency ? Route.snapFrequency(demandFrequency(route: route, type: type)) : route.frequency
        return max(1, Int((frequency / cycles - 0.01).rounded(.up)))
    }

    /// Aircraft flying only this route, beyond what it needs, that could go elsewhere.
    public func spareAircraft(routeID: Int) -> [Int] {
        guard let r = routeIndex(routeID), let needed = aircraftNeeded(routeID: routeID) else { return [] }
        let movable = routes[r].aircraftIDs.filter { id in aircraftIndex(id).map { isMovable($0) } ?? false }
        let extra = routes[r].aircraftIDs.count - needed
        guard extra > 0 else { return [] }
        // The newest go first, so the aircraft the route was built around stay on it.
        return Array(movable.sorted(by: >).prefix(extra))
    }

    /// Where each spare aircraft on this route would go, best first. Empty when there are none or nowhere earns more.
    public func spareMoves(routeID: Int) -> [SpareMove] {
        var copy = self
        return copy.moveSpares(routeID: routeID)
    }

    /// Moves this route's spare aircraft to the routes where they earn most. Returns what moved.
    @discardableResult
    public mutating func moveSpareAircraft(routeID: Int) throws -> [SpareMove] {
        guard routeIndex(routeID) != nil else { throw WorldError.unknownRoute(routeID) }
        let moves = moveSpares(routeID: routeID)
        for move in moves {
            if let i = aircraftIndex(move.aircraftID) { addNews(.fleetMoved, subject: aircraft[i].registration, amount: move.toRouteID) }
        }
        return moves
    }

    /// The fleet planner's Monday look at every route, before parked aircraft are placed.
    mutating func balanceFleet() {
        for routeID in routes.map(\.id).sorted() { _ = try? moveSpareAircraft(routeID: routeID) }
    }

    // MARK: Working it out

    mutating func moveSpares(routeID: Int) -> [SpareMove] {
        var moves: [SpareMove] = []
        for id in spareAircraft(routeID: routeID) {
            guard let i = aircraftIndex(id), let type = aircraft[i].type, let to = bestRouteForSpare(i, type: type, leaving: routeID) else { continue }
            do {
                try assign(aircraftID: id, toRoute: to.id)
            } catch {
                continue
            }
            moves.append(SpareMove(aircraftID: id, fromRouteID: routeID, toRouteID: to.id, gainPerDay: Int(to.gain.rounded())))
        }
        // Schedules the player set by hand stay as they are.
        for id in moves.isEmpty ? [] : [routeID] + moves.map(\.toRouteID) {
            if let r = routeIndex(id), routes[r].autoFrequency { try? applySuggestedFrequency(routeID: id) }
        }
        return moves
    }

    /// The route where one more of these aircraft adds the most profit a day, if any adds some.
    func bestRouteForSpare(_ i: Int, type: AircraftType, leaving routeID: Int) -> (id: Int, gain: Double)? {
        var best: (id: Int, gain: Double)?
        for route in routes where route.id != routeID && assignProblem(aircraftID: aircraft[i].id, routeID: route.id) == nil {
            // Only routes flown by the same kind of aircraft, or by none, so a schedule is never worked out for a mix.
            if let other = routeType(route), other.id != type.id { continue }
            let now = route.aircraftIDs.count
            let with = forecast(route: route, type: type, aircraftCount: now + 1, suggestedSchedule: true)
            guard with.isViable else { continue }
            let without = now == 0 ? 0 : forecast(route: route, type: type, aircraftCount: now, suggestedSchedule: true).profitPerDay
            let gain = with.profitPerDay - without
            if gain > Tuning.spareMoveMinGainPerDay, gain > (best?.gain ?? 0) { best = (route.id, gain) }
        }
        return best
    }

    /// The type flying the route: its first aircraft's.
    func routeType(_ route: Route) -> AircraftType? {
        route.aircraftIDs.lazy.compactMap { id in self.aircraft.first { $0.id == id }?.type }.first
    }

    /// An aircraft that flies one route and nothing else is going on: no job, no repair, no restoration.
    func isMovable(_ i: Int) -> Bool {
        let plane = aircraft[i]
        guard plane.isDelivered, plane.jobID == nil, !plane.awaitingRestoration, plane.otherRouteIDs.isEmpty else { return false }
        switch plane.status {
        case .grounded, .maintenance, .onOrder: return false
        case .idle, .boarding, .flying: return true
        }
    }
}

extension Tuning {
    /// A spare aircraft moves only when the new route earns at least this much more a day with it.
    public static let spareMoveMinGainPerDay = 100.0
}
