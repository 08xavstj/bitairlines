import CoreCatalog
import CoreWorld

/// Plain words for which aircraft can fly a job or a route, the empty flight it needs first, and why the others cannot.
enum PlaneChoiceWords {
    /// "about 3h" style hours for a plan.
    static func about(_ hours: Double) -> String { "about " + Format.wait(minutes: max(1, Int((hours * 60).rounded()))) }

    /// The empty flight before the work starts, or nil when the aircraft is (or is landing) there already.
    /// "Flies empty to Yellowknife, about 3h" or "Flies empty via Norman Wells (1 stop), about 5h".
    static func ferry(_ plan: FerryPlan?) -> String? {
        guard let plan, let last = plan.destination else { return nil }
        let time = about(plan.hours)
        if plan.stopsOnTheWay == 0 { return "Flies empty to \(Place.name(last)), \(time)" }
        let stops = plan.hops.dropLast()
        let count = "\(stops.count) stop\(stops.count == 1 ? "" : "s")"
        let names = stops.count <= 2 ? Place.list(Array(stops), separator: " and ") + " (\(count))" : count
        return "Flies empty via \(names), \(time)"
    }

    /// What an aircraft that can take a job will do: the way to the pickup, then the job itself.
    static func jobPlan(_ choice: PlaneChoice, job: Job, jobHours: Double?) -> String {
        let flight = jobHours.map { ", " + about($0) } ?? ""
        if let line = ferry(choice.ferry) { return "\(line), then the job\(flight)." }
        return "Starts at \(Place.name(job.from)): the job\(flight)."
    }

    /// What an aircraft that can join a route does first.
    static func routePlan(_ plan: FerryPlan?) -> String {
        if let line = ferry(plan) { return "\(line), then flies the route." }
        return "Already at a stop on this route."
    }

    /// A short reason an aircraft cannot do a job, in lower case to follow "Cannot fly it: ".
    static func jobReason(_ error: WorldError, job: Job, plane: Aircraft) -> String {
        if case .outOfRange = error, let type = plane.type, let a = AirportCatalog.airport(job.from), let b = AirportCatalog.airport(job.to),
           type.canFly(km: a.distanceKm(to: b)) {
            return "no way to get to \(Place.name(job.from)) empty, even with fuel stops"
        }
        return reason(error)
    }

    /// A short reason an aircraft cannot join a route, in lower case.
    static func routeReason(_ error: WorldError, route: Route, plane: Aircraft, in world: World) -> String {
        if case .outOfRange = error, let type = plane.type, world.fitProblem(type: type, route: route, kits: plane.kits) == nil {
            return "no way to get to this route empty, even with fuel stops"
        }
        return reason(error)
    }

    /// A short reason in lower case. Anything not listed falls back to the full message.
    static func reason(_ error: WorldError) -> String {
        switch error {
        case .notEnoughRoom: return "too few seats or too small a hold"
        case .aircraftCannotUse(let airport): return "cannot use \(Place.name(airport)) (runway too short or wrong surface)"
        case .outOfRange(let km): return "too far (\(Format.number(km)) km)"
        case .aircraftBusy: return "busy (on a job, broken down or in the hangar)"
        case .notDelivered: return "not arrived yet"
        case .noFuel(let airport): return "no fuel for long enough after \(Place.name(airport))"
        case .tooManyRoutes: return "already flies \(World.maxRoutesPerAircraft) routes"
        case .routesDoNotMeet: return "this route does not touch its other routes"
        case .jobUnavailable: return "the job is gone"
        default: return Messages.describe(error)
        }
    }

    /// How close a reason is to "it could fly it": a busy aircraft is closest, one that cannot get there at all is furthest.
    static func rank(_ error: WorldError) -> Int {
        switch error {
        case .aircraftBusy, .notDelivered: return 0
        case .notEnoughRoom: return 1
        case .aircraftCannotUse: return 2
        case .outOfRange: return 3
        default: return 4
        }
    }

    /// The line under a job on the board: who can fly it, or why nobody can. `planes` is the fleet by id (`planesByID`, built once
    /// per screen, so each job does not search the fleet again).
    static func jobFlyers(_ choices: [PlaneChoice], job: Job, planes: [Int: Aircraft]) -> (text: String, good: Bool) {
        let able = choices.filter(\.canDo).compactMap { planes[$0.aircraftID]?.registration }
        if !able.isEmpty { return ("Can fly it: " + able.joined(separator: ", "), true) }
        if planes.isEmpty { return ("You have no aircraft yet.", false) }
        let blocked = choices.compactMap { c -> (Int, String)? in
            guard let problem = c.problem, let plane = planes[c.aircraftID] else { return nil }
            return (rank(problem), jobReason(problem, job: job, plane: plane))
        }
        let closest = blocked.min { $0.0 < $1.0 }?.1 ?? "no reason known"
        return ("None of your aircraft can fly this: \(closest).", false)
    }

    /// The fleet by id, to look aircraft up without searching the whole fleet each time (if an id were ever repeated, the first wins,
    /// as with `first(where:)`).
    static func planesByID(_ world: World) -> [Int: Aircraft] {
        Dictionary(world.aircraft.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
