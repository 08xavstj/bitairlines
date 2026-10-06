import CoreCatalog
import CoreWorld

/// Remembers which aircraft can fly each job and each route, one aircraft at a time, so the screens do not plan every empty flight
/// again on each clock tick. An answer is kept while nothing it depends on changes:
/// - the job (from, to, the load, taken or not, still on offer) or the route (its stops),
/// - the aircraft (`PlaneKey`: where it will next be on the ground, whether it is free, its type, kits and routes),
/// - the airline-wide things (`WorldKey`: the month for frozen lakes, the game mode, the bases, the perks).
/// So an aircraft taking off re-plans that one aircraft, not the whole board, and the clock alone changes nothing.
@MainActor
final class PlaneChoiceCache {
    static let shared = PlaneChoiceCache()

    /// What every answer depends on. When it changes, everything is worked out again.
    struct WorldKey: Hashable {
        var month: Int
        var mode: GameMode
        var bases: [Base]
        var perks: [Perk]
    }

    /// What one aircraft brings to an answer.
    struct PlaneKey: Hashable {
        var id: Int
        var typeID: String
        var kits: [Kit]
        /// Where it will next be on the ground. Changes once a leg, when it takes off.
        var ground: String
        /// 0 free (parked, boarding or flying), 1 on order, 2 grounded, 3 in the hangar.
        var state: Int
        var jobID: Int?
        var restoring: Bool
        var routeIDs: [Int]
    }

    /// What a job brings to an answer (the things World.jobProblem reads).
    struct JobKey: Hashable {
        var id: Int
        var from: String
        var to: String
        var passengers: Int
        var cargoKg: Int
        var taken: Bool
        var onOffer: Bool
    }

    struct JobPair: Hashable {
        var job: JobKey
        var plane: PlaneKey
    }

    struct RoutePair: Hashable {
        var routeID: Int
        var stops: [String]
        var plane: PlaneKey
    }

    /// Old answers pile up as aircraft fly; past this many they are all dropped and worked out again when asked.
    private static let maxKept = 4_000

    private var worldKey: WorldKey?
    private var jobAnswers: [JobPair: PlaneChoice] = [:]
    private var routeAnswers: [RoutePair: PlaneChoice] = [:]

    /// The choices for every job on the board, keyed by job id: those that can fly it first, then the others, in fleet order.
    func jobChoices(world: World) -> [Int: [PlaneChoice]] {
        refresh(world)
        let planes = world.aircraft.map { PlaneChoiceCache.planeKey($0, in: world) }
        let old = jobAnswers
        var kept: [JobPair: PlaneChoice] = [:]
        var result: [Int: [PlaneChoice]] = [:]
        for job in world.ops.jobs where !job.isTaken {
            let key = PlaneChoiceCache.jobKey(job, in: world)
            let list = planes.map { plane -> PlaneChoice in
                let pair = JobPair(job: key, plane: plane)
                let answer = old[pair] ?? world.planeChoice(aircraftID: plane.id, jobID: job.id)
                kept[pair] = answer
                return answer
            }
            result[job.id] = PlaneChoiceCache.ordered(list)
        }
        // Only the answers for the board as it is now are kept.
        jobAnswers = kept
        return result
    }

    /// The choices for one job (worked out on the spot if the job is not on the board).
    func choices(world: World, jobID: Int) -> [PlaneChoice] {
        refresh(world)
        guard let job = world.ops.jobs.first(where: { $0.id == jobID }) else { return world.planeChoices(forJob: jobID) }
        let key = PlaneChoiceCache.jobKey(job, in: world)
        let list = world.aircraft.map { plane -> PlaneChoice in
            let pair = JobPair(job: key, plane: PlaneChoiceCache.planeKey(plane, in: world))
            if let saved = jobAnswers[pair] { return saved }
            let made = world.planeChoice(aircraftID: plane.id, jobID: job.id)
            jobAnswers[pair] = made
            return made
        }
        trim()
        return PlaneChoiceCache.ordered(list)
    }

    /// Every aircraft weighed for a route: those that can fly it first, then the others with the reason, each group in fleet order.
    func routeChoices(world: World, routeID: Int) -> [PlaneChoice] {
        refresh(world)
        guard let route = world.routes.first(where: { $0.id == routeID }) else { return [] }
        let list = world.aircraft.map { routeAnswer(world: world, route: route, plane: $0) }
        trim()
        return PlaneChoiceCache.ordered(list)
    }

    /// One aircraft weighed for every route, keyed by route id (the aircraft sheet shows one aircraft, so it plans only that one).
    func routeChoices(world: World, aircraftID: Int) -> [Int: PlaneChoice] {
        refresh(world)
        guard let plane = world.aircraft.first(where: { $0.id == aircraftID }) else { return [:] }
        var result: [Int: PlaneChoice] = [:]
        for route in world.routes { result[route.id] = routeAnswer(world: world, route: route, plane: plane) }
        trim()
        return result
    }

    private func routeAnswer(world: World, route: Route, plane: Aircraft) -> PlaneChoice {
        let pair = RoutePair(routeID: route.id, stops: route.stops, plane: PlaneChoiceCache.planeKey(plane, in: world))
        if let saved = routeAnswers[pair] { return saved }
        let made = world.planeChoice(aircraftID: plane.id, routeID: route.id)
        routeAnswers[pair] = made
        return made
    }

    /// Forgets everything when an airline-wide thing changed.
    private func refresh(_ world: World) {
        let now = WorldKey(month: world.clock.date.month, mode: world.ops.mode, bases: world.ops.bases, perks: world.ops.perks)
        guard now != worldKey else { return }
        worldKey = now
        jobAnswers = [:]
        routeAnswers = [:]
    }

    private func trim() {
        if jobAnswers.count > PlaneChoiceCache.maxKept { jobAnswers = [:] }
        if routeAnswers.count > PlaneChoiceCache.maxKept { routeAnswers = [:] }
    }

    /// Those that can do it first, then the others, each group in the order given (as World.planeChoices does).
    static func ordered(_ list: [PlaneChoice]) -> [PlaneChoice] {
        list.filter(\.canDo) + list.filter { !$0.canDo }
    }

    static func planeKey(_ plane: Aircraft, in world: World) -> PlaneKey {
        let state: Int
        switch plane.status {
        case .idle, .boarding, .flying: state = 0
        case .onOrder: state = 1
        case .grounded: state = 2
        case .maintenance: state = 3
        }
        return PlaneKey(id: plane.id, typeID: plane.typeID, kits: plane.kits, ground: world.nextGround(of: plane), state: state, jobID: plane.jobID,
                        restoring: plane.awaitingRestoration, routeIDs: plane.allRouteIDs)
    }

    static func jobKey(_ job: Job, in world: World) -> JobKey {
        JobKey(id: job.id, from: job.from, to: job.to, passengers: job.passengers, cargoKg: job.cargoKg, taken: job.isTaken,
               onOffer: job.expiresMinute > world.clock.minute)
    }
}
