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
        // A slot airport where the airline holds no slots: nobody may leave from it, so the job is not on offer to this airline.
        if !canDepartOnJob(from: from) { return .jobUnavailable }
        let cap = Capability(type: type, kits: plane.kits)
        let month = clock.date.month
        if !canUse(cap, at: from, month: month) { return .aircraftCannotUse(airport: from.code) }
        if !canUse(cap, at: to, month: month) { return .aircraftCannotUse(airport: to.code) }
        let km = from.distanceKm(to: to)
        if !type.canFly(km: km) { return .outOfRange(km: Int(km)) }
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
        airline.reputation = max(0, airline.reputation - 0.3)
    }

    /// The departure step for an aircraft on a job: fly to the pickup, or load and go.
    /// Before loading, the same checks as a route departure (depart() in Flights.swift): weather, frozen lakes this month, the
    /// check when worn, the crew day, daylight, slots, pilots and the breakdown roll. A heavy check waits until the job is done.
    /// Waiting can make the job late; it then pays half (landOnJob).
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
            // Fly empty towards the pickup, one hop at a time: on landing at a stop on the way this runs again.
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
        // Frozen lake this month: a floatplane waits for the thaw (checked again on the first of next month). Airports it can
        // never use were handled above.
        let cap = Capability(type: type, kits: aircraft[i].kits)
        let month = clock.date.month
        if !canUse(cap, at: from, month: month) || !canUse(cap, at: to, month: month) {
            aircraft[i].status = .boarding(until: firstOfNextMonth())
            return
        }
        // Scheduled check when worn (HeavyChecks.swift).
        if startCheckIfWorn(i) { return }
        // Crew day: no more flying today, resume early tomorrow.
        let km = from.distanceKm(to: to)
        let blockMinutes = max(1, Int((type.blockHours(km: km) * 60).rounded()))
        let dayLimit = Int(Tuning.maxBlockHoursPerDay(level: type.level) * 60)
        let tomorrowMorning = (clock.dayIndex + 1) * GameClock.minutesPerDay + 6 * 60
        if aircraft[i].blockMinutesToday > 0 && aircraft[i].blockMinutesToday + blockMinutes > dayLimit {
            aircraft[i].status = .boarding(until: tomorrowMorning)
            return
        }
        // Daylight at unlit strips, and the day's slots at busy airports.
        if let wait = darkHold(from: from, to: to, blockMinutes: blockMinutes) {
            aircraft[i].status = .boarding(until: wait)
            return
        }
        if outOfSlots(at: from) {
            aircraft[i].status = .boarding(until: tomorrowMorning)
            return
        }
        if !crewReady(i) {
            aircraft[i].status = .boarding(until: crewBackMinute(i) ?? clock.minute + GameClock.minutesPerDay)
            addNews(.noCrew, subject: aircraft[i].registration, amount: aircraft[i].id)
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
        airline.reputation = min(100, max(0, airline.reputation + (onTime ? 0.3 * reputationFactor : -0.5)))
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
