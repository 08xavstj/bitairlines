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
        if plane.jobID != nil || plane.awaitingRestoration { return .aircraftBusy }
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
        // A slot airport where the airline holds no slots: no aircraft could ever leave it, so the job is not on offer to this
        // airline (makeJob no longer offers such jobs; this catches slots sold after the offer).
        if !canDepartOnJob(from: from) { return .jobUnavailable }
        // Getting to the pickup may take stops on the way (FerryPlan.swift); it fails only when no chain of stops reaches it.
        if let problem = positioningProblem(aircraftIndex: i, toAny: [from.code]) { return problem }
        // Realism: fuel from the last stop before the pickup, through the job and back (JobFit.swift).
        if let dry = jobTripFuelProblem(aircraftIndex: i, type: type, from: from, to: to) { return dry }
        return nil
    }

    /// Puts an aircraft on a job. It leaves its route until the job is done, then goes back to it.
    public mutating func takeJob(jobID: Int, aircraftID: Int) throws {
        if let problem = jobProblem(jobID: jobID, aircraftID: aircraftID) { throw problem }
        guard let j = ops.jobs.firstIndex(where: { $0.id == jobID }), let i = aircraftIndex(aircraftID) else { throw WorldError.jobUnavailable }
        ops.jobs[j].aircraftID = aircraftID
        // A dispatch or seasonal job sat on the board by real time: its deadline starts when it is taken.
        if ops.jobs[j].isSpecial {
            ops.jobs[j].deadlineMinute = max(ops.jobs[j].deadlineMinute, clock.minute + Tuning.specialJobDeadlineMinutes)
        }
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

    /// Gives a job back before the load is on board. It costs a little reputation. A dispatch or event job goes back on the board
    /// instead, at no cost, so another aircraft can take it (it follows the real calendar, and there is no other way to change
    /// the aircraft on it).
    public mutating func dropJob(jobID: Int) throws {
        guard let j = ops.jobs.firstIndex(where: { $0.id == jobID }), !ops.jobs[j].loaded else { throw WorldError.jobUnavailable }
        if let planeID = ops.jobs[j].aircraftID, let i = aircraftIndex(planeID) { endJob(aircraftIndex: i) }
        if ops.jobs[j].isSpecial {
            ops.jobs[j].aircraftID = nil
            return
        }
        ops.jobs.remove(at: j)
        airline.reputation = max(0, airline.reputation - Tuning.reputationPerDroppedJob)
    }

    /// The departure step for an aircraft on a job: fly to the pickup, or load and go.
    /// Before loading it goes through the same take-off gate as a route leg (Flights.swift): weather, a frozen lake this month,
    /// the check when worn, the crew day, daylight, the day's slots, a pilot, then the breakdown roll. A heavy check waits
    /// until the job is done. Waiting can make the job late; it then pays half (landOnJob).
    mutating func departOnJob(_ i: Int, jobID: Int) {
        guard let j = ops.jobs.firstIndex(where: { $0.id == jobID }), let type = aircraft[i].type,
              let from = AirportCatalog.airport(ops.jobs[j].from), let to = AirportCatalog.airport(ops.jobs[j].to) else {
            endJob(aircraftIndex: i)
            return
        }
        let job = ops.jobs[j]
        // Something changed for good since it was taken (a kit came off, a runway extension, paving, the slots or a fuel depot
        // went): give the job back with a news line instead of waiting for ever.
        if let reason = jobGiveUpReason(aircraftIndex: i, from: from, to: to) {
            giveUpJob(aircraftIndex: i, jobIndex: j, reason: reason)
            return
        }
        if aircraft[i].location != job.from {
            // Fly empty towards the pickup, one hop at a time: on landing at a stop on the way this runs again. When no chain
            // of stops reaches the pickup from here, the job goes back and the news says so.
            if !startFerry(index: i, to: job.from) { giveUpJob(aircraftIndex: i, jobIndex: j, reason: .noWayThere) }
            return
        }
        // The take-off gate, first part: weather at either end, a frozen lake this month (a floatplane waits for the thaw,
        // checked again on the first of next month). Airports it can never use were handled above.
        if let wait = airportHold(from: from, to: to, cap: Capability(type: type, kits: aircraft[i].kits)) {
            aircraft[i].status = .boarding(until: wait)
            return
        }
        // Scheduled check when worn (HeavyChecks.swift).
        if startCheckIfWorn(i) { return }
        // The gate, second part: the crew day, daylight at unlit strips, the day's slots at the pickup, a pilot.
        let km = from.distanceKm(to: to)
        let blockMinutes = max(1, Int((type.blockHours(km: km) * 60).rounded()))
        if let wait = crewHold(i, type: type, from: from, to: to, blockMinutes: blockMinutes) {
            aircraft[i].status = .boarding(until: wait)
            return
        }
        // Failure on the ground, drawn from the added systems' stream (ops.rng) and always drawn, like depart().
        let wear = (1.0 + (100.0 - aircraft[i].condition) / 25.0) * heavyCheckWear(aircraft[i])
        if ops.rng.unit() < Tuning.breakdownPerDeparture * wear {
            raiseBreakdown(aircraftIndex: i, type: type)
            return
        }
        useSlot(at: from)
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
        // On time earns a little (Reputation.swift sets the numbers); late costs more than that.
        let change = onTime ? Tuning.reputationPerJobOnTime * reputationFactor : -Tuning.reputationPerLateJob
        airline.reputation = min(100, max(0, airline.reputation + change))
        ops.jobsDone.append(JobRecord(kind: job.kind, to: job.to, cargoKg: job.cargoKg, onTime: onTime, day: clock.dayIndex))
        if ops.jobsDone.count > Tuning.jobRecordsKept { ops.jobsDone.removeFirst(ops.jobsDone.count - Tuning.jobRecordsKept) }
        addNews(onTime ? .jobDone : .jobLate, subject: job.to, amount: onTime ? job.pay : job.pay / 2)
        ops.jobs.remove(at: j)
        // A daily dispatch earns its stamp and a seasonal job counts towards its livery, late or not (DailyDispatch.swift).
        noteSpecialJobDone(job)
        aircraft[i].status = .idle
        endJob(aircraftIndex: i)
        return true
    }

    /// The aircraft is free again: back to the routes it flew before the job (those that still exist and still fit).
    /// Only an aircraft waiting at the gate changes state here: one in the air rejoins its routes when it lands, and one in the
    /// hangar or grounded by a breakdown stays there until that is over (finishMaintenance then sends it back to its routes).
    mutating func endJob(aircraftIndex i: Int) {
        aircraft[i].jobID = nil
        aircraft[i].ferryTargetStore = nil
        let back = aircraft[i].returnRouteID.map { [$0] } ?? []
        let others = aircraft[i].returnOtherRoutesStore ?? []
        aircraft[i].returnRouteID = nil
        aircraft[i].returnOtherRoutesStore = nil
        if case .boarding = aircraft[i].status { aircraft[i].status = .idle }
        rejoinRoutes(aircraftIndex: i, routeIDs: back + others)
    }

    /// Puts an aircraft that is on no route back on these routes, in order: the first that still exists and fits becomes its
    /// current route, the others it flies too while they share an airport with those already kept (the shared-aircraft rules).
    /// A shared aircraft whose main route was closed while it was away keeps the rest. An idle aircraft looks for its next
    /// departure at once (depart() flies it to the route if it is somewhere else, or parks it if it cannot get there).
    mutating func rejoinRoutes(aircraftIndex i: Int, routeIDs: [Int]) {
        guard aircraft[i].routeID == nil, let type = aircraft[i].type else { return }
        let kits = aircraft[i].kits
        var kept: [Int] = []
        for rid in routeIDs where !kept.contains(rid) && kept.count < World.maxRoutesPerAircraft {
            guard let r = routeIndex(rid), fitProblem(type: type, route: routes[r], kits: kits) == nil else { continue }
            if !kept.isEmpty && !meets(routes[r], kept) { continue }
            kept.append(rid)
        }
        guard let first = kept.first else { return }
        let id = aircraft[i].id
        aircraft[i].routeID = first
        aircraft[i].otherRouteIDs = Array(kept.dropFirst())
        for rid in kept {
            if let r = routeIndex(rid), !routes[r].aircraftIDs.contains(id) { routes[r].aircraftIDs.append(id) }
        }
        refreshAutoFrequency(routeIDs: kept)
        if case .idle = aircraft[i].status { aircraft[i].status = .boarding(until: clock.minute) }
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
