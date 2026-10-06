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
        planeChoice(aircraftID: aircraftID, routeID: routeID).problem
    }

    /// One aircraft weighed for a route: why it cannot be put on it, or the empty flight it needs first. The way there is searched
    /// once and gives both answers.
    public func planeChoice(aircraftID: Int, routeID: Int) -> PlaneChoice {
        func cannot(_ problem: WorldError) -> PlaneChoice { PlaneChoice(aircraftID: aircraftID, problem: problem, ferry: nil) }
        guard let i = aircraftIndex(aircraftID) else { return cannot(.unknownAircraft(aircraftID)) }
        guard let r = routeIndex(routeID) else { return cannot(.unknownRoute(routeID)) }
        let plane = aircraft[i]
        guard plane.isDelivered else { return cannot(.notDelivered) }
        if case .grounded = plane.status { return cannot(.aircraftBusy) }
        guard let type = plane.type else { return cannot(.unknownType(plane.typeID)) }
        if plane.jobID != nil || plane.awaitingRestoration { return cannot(.aircraftBusy) }
        if let problem = fitProblem(type: type, route: routes[r], kits: plane.kits) { return cannot(problem) }
        let way = positioning(aircraftIndex: i, toAny: routes[r].stops)
        if let problem = way.problem { return cannot(problem) }
        return PlaneChoice(aircraftID: aircraftID, problem: nil, ferry: way.plan)
    }

    /// One aircraft weighed for a job: why it cannot take it, or the empty flight to the pickup.
    public func planeChoice(aircraftID: Int, jobID: Int) -> PlaneChoice {
        let problem = jobProblem(jobID: jobID, aircraftID: aircraftID)
        guard problem == nil, let job = ops.jobs.first(where: { $0.id == jobID }) else {
            return PlaneChoice(aircraftID: aircraftID, problem: problem, ferry: nil)
        }
        return PlaneChoice(aircraftID: aircraftID, problem: nil, ferry: ferryPlan(aircraftID: aircraftID, toAny: [job.from]))
    }

    /// Every aircraft weighed for a route: those that can fly it first, then the others with the reason, each group in fleet order.
    public func planeChoices(forRoute routeID: Int) -> [PlaneChoice] {
        guard routeIndex(routeID) != nil else { return [] }
        let choices = aircraft.map { planeChoice(aircraftID: $0.id, routeID: routeID) }
        return choices.filter(\.canDo) + choices.filter { !$0.canDo }
    }

    /// Every aircraft weighed for a job: those that can fly it first, then the others with the reason, each group in fleet order.
    public func planeChoices(forJob jobID: Int) -> [PlaneChoice] {
        guard ops.jobs.contains(where: { $0.id == jobID }) else { return [] }
        let choices = aircraft.map { planeChoice(aircraftID: $0.id, jobID: jobID) }
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
