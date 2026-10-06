// CoreWorld/JobFlights.swift: flying a job. The aircraft leaves its route (if it has one), flies empty to the pickup if it has to,
// carries the load, is paid on landing (half if late), and then goes back to its route by itself.
import CoreCatalog
import CoreSim

extension World {
    /// Why this aircraft cannot take this job (nil if it can).
    public func jobProblem(jobID: Int, aircraftID: Int) -> WorldError? {
        guard let job = ops.jobs.first(where: { $0.id == jobID }), !job.isTaken, job.expiresMinute > clock.minute else { return .jobUnavailable }
        guard let i = aircraftIndex(aircraftID) else { return .unknownAircraft(aircraftID) }
        let plane = aircraft[i]
        guard plane.isDelivered else { return .notDelivered }
        if plane.jobID != nil { return .aircraftBusy }
        switch plane.status {
        case .grounded, .maintenance, .onOrder: return .aircraftBusy
        case .idle, .boarding, .flying: break
        }
        guard let type = plane.type, let from = AirportCatalog.airport(job.from), let to = AirportCatalog.airport(job.to) else { return .unknownAirport(job.from) }
        if plane.seats < job.passengers || plane.cargoKg < job.cargoKg { return .notEnoughRoom }
        let cap = Capability(type: type, kits: plane.kits)
        let month = clock.date.month
        if !canUse(cap, at: from, month: month) { return .aircraftCannotUse(airport: from.code) }
        if !canUse(cap, at: to, month: month) { return .aircraftCannotUse(airport: to.code) }
        let km = from.distanceKm(to: to)
        if !type.canFly(km: km) { return .outOfRange(km: Int(km)) }
        let start = plane.flight?.to ?? plane.location
        if start != from.code, let here = AirportCatalog.airport(start) {
            let ferry = here.distanceKm(to: from)
            if !type.canFly(km: ferry) { return .outOfRange(km: Int(ferry)) }
        }
        return nil
    }

    /// Puts an aircraft on a job. It leaves its route until the job is done, then goes back to it.
    public mutating func takeJob(jobID: Int, aircraftID: Int) throws {
        if let problem = jobProblem(jobID: jobID, aircraftID: aircraftID) { throw problem }
        guard let j = ops.jobs.firstIndex(where: { $0.id == jobID }), let i = aircraftIndex(aircraftID) else { throw WorldError.jobUnavailable }
        ops.jobs[j].aircraftID = aircraftID
        if let rid = aircraft[i].routeID, routeIndex(rid) != nil {
            aircraft[i].returnRouteID = rid
            let others = aircraft[i].otherRouteIDs
            aircraft[i].returnOtherRoutesStore = others.isEmpty ? nil : others
        }
        detachFromAllRoutes(i)
        aircraft[i].jobID = jobID
        switch aircraft[i].status {
        case .idle, .boarding: aircraft[i].status = .boarding(until: clock.minute)
        default: break
        }
    }

    /// Gives a job back before the load is on board. It costs a little reputation.
    public mutating func dropJob(jobID: Int) throws {
        guard let j = ops.jobs.firstIndex(where: { $0.id == jobID }), !ops.jobs[j].loaded else { throw WorldError.jobUnavailable }
        if let planeID = ops.jobs[j].aircraftID, let i = aircraftIndex(planeID) { endJob(aircraftIndex: i) }
        ops.jobs.remove(at: j)
        airline.reputation = max(0, airline.reputation - 0.3)
    }

    /// The departure step for an aircraft on a job: fly to the pickup, or load and go.
    mutating func departOnJob(_ i: Int, jobID: Int) {
        guard let j = ops.jobs.firstIndex(where: { $0.id == jobID }), let type = aircraft[i].type,
              let from = AirportCatalog.airport(ops.jobs[j].from), let to = AirportCatalog.airport(ops.jobs[j].to) else {
            endJob(aircraftIndex: i)
            return
        }
        let job = ops.jobs[j]
        if aircraft[i].location != job.from {
            if !startFerry(index: i, to: job.from) {
                ops.jobs[j].aircraftID = nil
                endJob(aircraftIndex: i)
            }
            return
        }
        if let until = closureEnd(of: job.from) ?? closureEnd(of: job.to) {
            aircraft[i].status = .boarding(until: until)
            return
        }
        let km = from.distanceKm(to: to)
        let blockMinutes = max(1, Int((type.blockHours(km: km) * 60).rounded()))
        if let wait = darkHold(from: from, to: to, blockMinutes: blockMinutes) {
            aircraft[i].status = .boarding(until: wait)
            return
        }
        if !crewReady(i) {
            aircraft[i].status = .boarding(until: crewBackMinute(i) ?? clock.minute + GameClock.minutesPerDay)
            addNews(.noCrew, subject: aircraft[i].registration, amount: aircraft[i].id)
            return
        }
        let costs = legCost(type: type, aircraftIndex: i, from: from, to: to, km: km)
        aircraft[i].flight = Flight(from: job.from, to: job.to, departedMinute: clock.minute, distanceKm: km, passengers: job.passengers, cargoKg: job.cargoKg,
                                    revenue: 0, cost: Int(costs.rounded()), isFerry: false)
        ops.jobs[j].loaded = true
        aircraft[i].blockMinutesToday += blockMinutes
        aircraft[i].status = .flying(until: clock.minute + blockMinutes)
    }

    /// Called on landing when the aircraft is on a job. True if this landing finished the job.
    mutating func landOnJob(_ i: Int, flight: Flight) -> Bool {
        guard let jobID = aircraft[i].jobID, let j = ops.jobs.firstIndex(where: { $0.id == jobID }) else { return false }
        let job = ops.jobs[j]
        guard job.loaded, flight.to == job.to else { return false }
        let onTime = clock.minute <= job.deadlineMinute
        earn(onTime ? job.pay : job.pay / 2)
        airline.stats.passengers += job.passengers
        airline.stats.cargoKg += job.cargoKg
        airline.stats.flights += 1
        airline.reputation = min(100, max(0, airline.reputation + (onTime ? 0.3 * reputationFactor : -0.5)))
        ops.jobsDone.append(JobRecord(kind: job.kind, to: job.to, cargoKg: job.cargoKg, onTime: onTime, day: clock.dayIndex))
        if ops.jobsDone.count > Tuning.jobRecordsKept { ops.jobsDone.removeFirst(ops.jobsDone.count - Tuning.jobRecordsKept) }
        addNews(onTime ? .jobDone : .jobLate, subject: job.to, amount: onTime ? job.pay : job.pay / 2)
        ops.jobs.remove(at: j)
        aircraft[i].status = .idle
        endJob(aircraftIndex: i)
        return true
    }

    /// The aircraft is free again: back to its old route if it had one.
    mutating func endJob(aircraftIndex i: Int) {
        aircraft[i].jobID = nil
        let back = aircraft[i].returnRouteID
        aircraft[i].returnRouteID = nil
        // An aircraft still in the air rejoins its route when it lands (assign leaves a flying aircraft to finish its flight).
        if case .flying = aircraft[i].status {} else { aircraft[i].status = .idle }
        let others = aircraft[i].returnOtherRoutesStore ?? []
        aircraft[i].returnOtherRoutesStore = nil
        if let back, routeIndex(back) != nil {
            try? assign(aircraftID: aircraft[i].id, toRoute: back)
            // A shared aircraft takes up its other routes again (those that still exist and still fit).
            for rid in others { try? addRoute(aircraftID: aircraft[i].id, routeID: rid) }
        }
    }
}

/// A finished job, kept for scenarios and the airline screen.
public struct JobRecord: Sendable, Hashable, Codable {
    public var kind: JobKind
    public var to: String
    public var cargoKg: Int
    public var onTime: Bool
    public var day: Int
}
