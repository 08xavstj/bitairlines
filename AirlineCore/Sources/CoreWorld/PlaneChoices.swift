// CoreWorld/PlaneChoices.swift: before the player picks an aircraft for a route or a job, which ones can do it, what empty flight
// each needs first, and why the others cannot. The actions (assign, takeJob) refuse for exactly these reasons, so a choice the app
// offers never ends in a refusal. Codes and numbers only; the app writes the words.
import CoreCatalog

/// One aircraft weighed for a piece of work.
public struct PlaneChoice: Sendable, Hashable, Identifiable {
    public var aircraftID: Int
    /// Why it cannot do it; nil if it can.
    public var problem: WorldError?
    /// The empty flight to where the work starts, when it can do it (empty hops when it is there already).
    public var ferry: FerryPlan?

    public var id: Int { aircraftID }
    public var canDo: Bool { problem == nil }
}

extension World {
    /// Why this aircraft cannot be put on this route now (nil if it can): not here yet, busy, the route's airports or legs do not
    /// suit it, or there is no way to fly there empty, even with stops on the way.
    public func assignProblem(aircraftID: Int, routeID: Int) -> WorldError? {
        guard let i = aircraftIndex(aircraftID) else { return .unknownAircraft(aircraftID) }
        guard let r = routeIndex(routeID) else { return .unknownRoute(routeID) }
        let plane = aircraft[i]
        guard plane.isDelivered else { return .notDelivered }
        if case .grounded = plane.status { return .aircraftBusy }
        guard let type = plane.type else { return .unknownType(plane.typeID) }
        if plane.jobID != nil || plane.awaitingRestoration { return .aircraftBusy }
        if let problem = fitProblem(type: type, route: routes[r], kits: plane.kits) { return problem }
        return positioningProblem(aircraftIndex: i, toAny: routes[r].stops)
    }

    /// Every aircraft weighed for a route: those that can fly it first, then the others with the reason, each group in fleet order.
    public func planeChoices(forRoute routeID: Int) -> [PlaneChoice] {
        guard let r = routeIndex(routeID) else { return [] }
        let stops = routes[r].stops
        let choices = aircraft.map { plane -> PlaneChoice in
            let problem = assignProblem(aircraftID: plane.id, routeID: routeID)
            return PlaneChoice(aircraftID: plane.id, problem: problem, ferry: problem == nil ? ferryPlan(aircraftID: plane.id, toAny: stops) : nil)
        }
        return choices.filter(\.canDo) + choices.filter { !$0.canDo }
    }

    /// Every aircraft weighed for a job: those that can fly it first, then the others with the reason, each group in fleet order.
    public func planeChoices(forJob jobID: Int) -> [PlaneChoice] {
        guard let job = ops.jobs.first(where: { $0.id == jobID }) else { return [] }
        let choices = aircraft.map { plane -> PlaneChoice in
            let problem = jobProblem(jobID: jobID, aircraftID: plane.id)
            return PlaneChoice(aircraftID: plane.id, problem: problem, ferry: problem == nil ? ferryPlan(aircraftID: plane.id, toAny: [job.from]) : nil)
        }
        return choices.filter(\.canDo) + choices.filter { !$0.canDo }
    }

    /// The aircraft that can take this job now, in fleet order.
    public func flyableAircraft(forJob jobID: Int) -> [Int] {
        aircraft.filter { jobProblem(jobID: jobID, aircraftID: $0.id) == nil }.map(\.id)
    }

    /// Block hours of the job's own flight for this aircraft (nil if the job or the aircraft is unknown).
    public func jobFlightHours(jobID: Int, aircraftID: Int) -> Double? {
        guard let job = ops.jobs.first(where: { $0.id == jobID }), let type = aircraft.first(where: { $0.id == aircraftID })?.type,
              let a = AirportCatalog.airport(job.from), let b = AirportCatalog.airport(job.to) else { return nil }
        return type.blockHours(km: a.distanceKm(to: b))
    }
}
