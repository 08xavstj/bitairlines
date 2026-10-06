import Foundation
import Observation
import CoreCatalog
import CoreWorld

/// The guided first route, in five steps. Where the player is comes from the world itself (routes, aircraft on them, flights flown), so the
/// guide cannot fall out of step with what they actually did, and nothing about it is stored in a save.
enum TutorialStep: Int, CaseIterable {
    case openRoute, assignAircraft, startClock, watch, review

    /// The rail button to light up.
    var section: GameSection? {
        switch self {
        case .openRoute: GameSection.map
        case .assignAircraft: GameSection.fleet
        case .review: GameSection.routes
        case .startClock, .watch: nil
        }
    }

    var highlightsSpeed: Bool { self == .startClock }
}

enum Tutorial {
    /// How many flights the player watches before the last step.
    static let flightsToWatch = 3

    /// The step the player is on, or nil once they have been through all of it. `reviewed` is true after they press Done on the last step.
    static func step(world: World, speed: GameSpeed, reviewed: Bool) -> TutorialStep? {
        if world.routes.isEmpty { return .openRoute }
        if world.routes.allSatisfy({ $0.aircraftIDs.isEmpty }) { return .assignAircraft }
        let flights = world.airline.stats.flights
        if flights < flightsToWatch { return speed == .paused ? .startClock : .watch }
        return reviewed ? nil : .review
    }

    /// A good first route from home for the starting aircraft: the nearby place where it would earn the most.
    static func suggestion(world: World) -> (code: String, perDay: Double)? {
        guard let home = AirportCatalog.airport(world.airline.home), let type = world.aircraft.first?.type else { return nil }
        var best: (code: String, perDay: Double)?
        for airport in AirportCatalog.all where airport.code != home.code {
            let km = home.distanceKm(to: airport)
            guard km < 600, type.canFly(km: km), type.canLand(at: airport) else { continue }
            let stops = [home.code, airport.code]
            guard world.routeProblem(stops: stops) == nil else { continue }
            let forecast = world.forecast(stops: stops, type: type)
            if forecast.isViable, forecast.profitPerDay > (best?.perDay ?? 0) { best = (airport.code, forecast.profitPerDay) }
        }
        return best
    }

    /// What the guide says on each step. Plain words, no jargon.
    static func text(for step: TutorialStep, world: World, suggestion: (code: String, perDay: Double)?, flights: Int) -> String {
        switch step {
        case .openRoute:
            var line = "Open your first route. On the Map press New route, then tap two airports in a row."
            if let suggestion {
                line += " Try \(Place.name(world.airline.home)) to \(Place.name(suggestion.code)), about \(Format.perDay(suggestion.perDay)) once people know it."
            }
            return line
        case .assignAircraft:
            return "Your aircraft is parked. Open Fleet, tap it, and press Assign next to your route. After that it flies the route on its own."
        case .startClock:
            return "Start the clock with 1x or 4x at the top. The game stops by itself if something needs a decision."
        case .watch:
            return "Watch it fly. You earn money when an aircraft lands. Flights so far: \(min(flights, Tutorial.flightsToWatch)) of \(Tutorial.flightsToWatch)."
        case .review:
            return "Your first flights are done. Routes shows what each route should earn. When there is cash, buy a used aircraft in Hangar and open another route."
        }
    }
}

/// Remembers, per save slot, that a new airline's guide is still running. Saves from before the guide existed never show it.
struct TutorialStore {
    var defaults: UserDefaults = .standard

    private func key(_ slot: Int) -> String { "tutorial.active.\(slot)" }
    func isActive(slot: Int) -> Bool { defaults.bool(forKey: key(slot)) }
    func setActive(_ on: Bool, slot: Int) { defaults.set(on, forKey: key(slot)) }
}

/// The guide while a game is open: which step it is on, and the Skip and Done buttons.
@MainActor
@Observable
final class TutorialCoach {
    private(set) var active: Bool
    private(set) var step: TutorialStep?
    private var reviewed = false
    private let slot: Int
    @ObservationIgnored private let store: TutorialStore

    init(slot: Int, store: TutorialStore = TutorialStore()) {
        self.slot = slot
        self.store = store
        active = store.isActive(slot: slot)
    }

    /// Follows the world. Ends the guide after the last step.
    func update(world: World, speed: GameSpeed) {
        guard active else { step = nil; return }
        step = Tutorial.step(world: world, speed: speed, reviewed: reviewed)
        if step == nil { finish() }
    }

    func done() { reviewed = true; finish() }

    func finish() {
        active = false
        step = nil
        store.setActive(false, slot: slot)
    }
}
