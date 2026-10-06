// CoreWorld/JobFit.swift: which aircraft can fly a job. One rule, used when a job is made (it is sized to an aircraft that can
// fly it), when an aircraft is offered for it (jobProblem in JobFlights.swift) and before each departure on a job (an aircraft
// that can never fly it gives it back): both airports usable, the distance within range, a slot to leave the pickup where the
// airport hands out slots, and in Realism fuel for the trip (the route rule, fuelProblem in RouteActions.swift).
import CoreCatalog

/// Why an aircraft gave a taken job back by itself. News subject "jobgone:<registration>:<airport the job went to>", amount the
/// raw value.
public enum JobGiveUpReason: Int, Sendable, Hashable, CaseIterable {
    /// It can no longer use one of the job's airports in any season (a kit came off, a runway extension or paving went).
    case cannotUseAirport = 0
    /// The airline holds no slots at the pickup any more.
    case noSlots = 1
    /// Realism: no fuel for the trip any more (a fuel depot went).
    case noFuel = 2
}

extension World {
    /// A job may leave from here: the airport hands out no slots, or the airline holds some there. (When the day's slots are
    /// used up the aircraft waits for tomorrow; with none held it would wait for ever.)
    func canDepartOnJob(from airport: Airport) -> Bool {
        !needsSlots(airport) || slotsHeld(at: airport.code) > 0
    }

    /// True while a job is on offer: not taken, its offer has not run out (the board is only cleared at midnight) and the airline
    /// may leave from its pickup.
    public func isOnOffer(_ job: Job) -> Bool {
        guard !job.isTaken, job.expiresMinute > clock.minute else { return false }
        guard let from = AirportCatalog.airport(job.from) else { return false }
        return canDepartOnJob(from: from)
    }

    /// The jobs on offer now, in board order: what the Jobs screen lists and counts.
    public var jobsOnOffer: [Job] { ops.jobs.filter { isOnOffer($0) } }

    /// Realism: the trip flown as a loop through `stops` keeps every stretch between fuel stops within range, the rule a route
    /// has. Nil when it does, or outside Realism.
    func jobFuelProblem(type: AircraftType, stops: [String]) -> WorldError? {
        guard ops.mode.fuelOnlyWhereSold, stops.count >= 2 else { return nil }
        var legs: [LegState] = []
        for (k, code) in stops.enumerated() {
            guard let a = AirportCatalog.airport(code), let b = AirportCatalog.airport(stops[(k + 1) % stops.count]) else { return .unknownAirport(code) }
            legs.append(LegState(from: a.code, to: b.code, distanceKm: a.distanceKm(to: b), marketPaxPerDay: 0, marketCargoKgPerDay: 0, marketFare: 0,
                                 waitingPax: 0, waitingCargoKg: 0, lastUpdate: clock.minute, maturity: 1, passengersCarried: 0, revenue: 0,
                                 departuresThisWeek: 0, departuresLastWeek: 0, nextSlot: clock.minute))
        }
        let loop = Route(id: 0, name: "", stops: stops, fareMultiplier: 1, carriesCargo: true, frequency: 1, autoFrequency: false, legs: legs,
                         aircraftIDs: [], openedDay: clock.dayIndex, flights: 0, revenueThisMonth: 0, costThisMonth: 0, revenueLastMonth: 0, costLastMonth: 0)
        return fuelProblem(type: type, route: loop)
    }

    /// Realism, for jobProblem: the trip from the airport the aircraft flies in from (the last stop on its way to the pickup, or
    /// where it is), through the job, and back there. Nil when it keeps within range between fuel stops, or outside Realism.
    func jobTripFuelProblem(aircraftIndex i: Int, type: AircraftType, from: Airport, to: Airport) -> WorldError? {
        guard ops.mode.fuelOnlyWhereSold else { return nil }
        let start = nextGround(of: aircraft[i])
        var stops = [from.code, to.code]
        if start != from.code, let plan = ferryPlan(aircraftIndex: i, from: start, toAny: [from.code]) {
            let hops = plan.hops
            let previous = hops.count >= 2 ? hops[hops.count - 2] : start
            if previous != to.code { stops.insert(previous, at: 0) }
        }
        return jobFuelProblem(type: type, stops: stops)
    }

    /// Whether aircraft `i` could fly a job from `from` to `to`: delivered and not waiting for restoration, within range, both
    /// airports usable (this month when `month` is given, else in some season) and, in Realism, fuel for the trip there and back.
    /// Room for the load and the pickup's slots are checked by the callers.
    func planeCanFlyJob(_ i: Int, from: Airport, to: Airport, month: Int?) -> Bool {
        let plane = aircraft[i]
        guard plane.isDelivered, !plane.awaitingRestoration, let type = plane.type, type.canFly(km: from.distanceKm(to: to)) else { return false }
        let cap = Capability(type: type, kits: plane.kits)
        guard canUse(cap, at: from, month: month), canUse(cap, at: to, month: month) else { return false }
        return jobFuelProblem(type: type, stops: [from.code, to.code]) == nil
    }

    /// The aircraft a new job between two airports is sized to: of those that can fly it this month, the one with the most seats
    /// (work that carries people) or the biggest hold (freight), the first in the fleet on a tie. Nil when none can.
    func jobSizingPlane(kind: JobKind, from: Airport, to: Airport) -> Aircraft? {
        let month = clock.date.month
        var best: Aircraft?
        var bestKey = (0, 0)
        for i in aircraft.indices where planeCanFlyJob(i, from: from, to: to, month: month) {
            let plane = aircraft[i]
            let key = kind.carriesPeople ? (plane.seats, plane.cargoKg) : (plane.cargoKg, plane.seats)
            guard key.0 > 0, best == nil || key > bestKey else { continue }
            best = plane
            bestKey = key
        }
        return best
    }

    /// True if some aircraft in the fleet could fly this job this month, load and all, and it may leave its pickup.
    func jobCanBeFlown(_ job: Job) -> Bool {
        guard let from = AirportCatalog.airport(job.from), let to = AirportCatalog.airport(job.to), canDepartOnJob(from: from) else { return false }
        let month = clock.date.month
        return aircraft.indices.contains { i in
            aircraft[i].seats >= job.passengers && aircraft[i].cargoKg >= job.cargoKg && planeCanFlyJob(i, from: from, to: to, month: month)
        }
    }

    /// Why aircraft `i` can never fly this job as things stand, or nil. Waits that end by themselves (weather, a frozen lake,
    /// the crew day, the day's slots used up) are not reasons.
    func jobGiveUpReason(aircraftIndex i: Int, from: Airport, to: Airport) -> JobGiveUpReason? {
        guard let type = aircraft[i].type else { return .cannotUseAirport }
        let cap = Capability(type: type, kits: aircraft[i].kits)
        if !canUse(cap, at: from) || !canUse(cap, at: to) || !type.canFly(km: from.distanceKm(to: to)) { return .cannotUseAirport }
        if !canDepartOnJob(from: from) { return .noSlots }
        if jobFuelProblem(type: type, stops: [from.code, to.code]) != nil { return .noFuel }
        return nil
    }

    /// The aircraft gives a taken job back by itself (it can never fly it): the job goes back on the board while its offer or its
    /// real day lasts, the aircraft goes back to its routes, and the news says why.
    mutating func giveUpJob(aircraftIndex i: Int, jobIndex j: Int, reason: JobGiveUpReason) {
        let job = ops.jobs[j]
        let registration = aircraft[i].registration
        if job.isSpecial || job.expiresMinute > clock.minute {
            ops.jobs[j].aircraftID = nil
            ops.jobs[j].loaded = false
        } else {
            ops.jobs.remove(at: j)
        }
        endJob(aircraftIndex: i)
        addNews(.milestone, subject: "jobgone:\(registration):\(job.to)", amount: reason.rawValue)
    }
}
