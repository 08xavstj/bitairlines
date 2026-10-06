import CoreCatalog
import CoreWorld

/// Remembers which aircraft can fly each job and each route, so the screens do not plan every empty flight again on each clock tick.
/// Everything is worked out again when the jobs, the routes, the fleet (where each aircraft will next be on the ground, what it is
/// doing, its kits), the bases, the game mode or the hour change.
@MainActor
final class PlaneChoiceCache {
    static let shared = PlaneChoiceCache()

    private var key = ""
    private var jobStore: [Int: [PlaneChoice]]?
    private var routeStore: [Int: [PlaneChoice]] = [:]

    /// The choices for every job on the board, keyed by job id.
    func jobChoices(world: World) -> [Int: [PlaneChoice]] {
        refresh(world)
        if let saved = jobStore { return saved }
        var fresh: [Int: [PlaneChoice]] = [:]
        for job in world.ops.jobs where !job.isTaken { fresh[job.id] = world.planeChoices(forJob: job.id) }
        jobStore = fresh
        return fresh
    }

    /// The choices for one job (worked out on the spot if the job was taken or is new).
    func choices(world: World, jobID: Int) -> [PlaneChoice] {
        jobChoices(world: world)[jobID] ?? world.planeChoices(forJob: jobID)
    }

    /// Every aircraft weighed for a route: those that can fly it first.
    func routeChoices(world: World, routeID: Int) -> [PlaneChoice] {
        refresh(world)
        if let saved = routeStore[routeID] { return saved }
        let fresh = world.planeChoices(forRoute: routeID)
        routeStore[routeID] = fresh
        return fresh
    }

    /// One aircraft weighed for a route.
    func choice(world: World, aircraftID: Int, routeID: Int) -> PlaneChoice? {
        routeChoices(world: world, routeID: routeID).first { $0.aircraftID == aircraftID }
    }

    private func refresh(_ world: World) {
        let now = Self.key(world)
        guard now != key else { return }
        key = now
        jobStore = nil
        routeStore = [:]
    }

    private static func key(_ world: World) -> String {
        let bases = world.ops.bases.map { base in base.airport + ":" + String(base.facilities.count) }.joined(separator: ",")
        var parts: [String] = [String(world.clock.minute / 60), String(describing: world.ops.mode), bases]
        for job in world.ops.jobs { parts.append("j\(job.id):\(job.aircraftID ?? -1)") }
        for route in world.routes { parts.append("r\(route.id):" + route.stops.joined(separator: ",")) }
        for plane in world.aircraft {
            parts.append("a\(plane.id):\(plane.typeID):\(world.nextGround(of: plane)):\(statusCode(plane.status)):\(plane.jobID ?? -1):\(plane.allRouteIDs):\(plane.kits.count):\(plane.awaitingRestoration)")
        }
        return parts.joined(separator: "|")
    }

    private static func statusCode(_ status: AircraftStatus) -> String {
        switch status {
        case .idle: return "i"
        case .boarding: return "b"
        case .flying: return "f"
        case .maintenance: return "m"
        case .grounded: return "g"
        case .onOrder: return "o"
        }
    }
}
