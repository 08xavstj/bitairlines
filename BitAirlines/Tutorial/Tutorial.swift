import Foundation
import Observation
import CoreCatalog
import CoreWorld

/// The guide for a new airline: the first route in four steps, then a short tour of what comes next. Where the player is comes from
/// the world itself (routes, aircraft, flights flown) plus the tips they have read, so the guide cannot fall out of step with what
/// they actually did. Nothing about it is stored in a save.
enum TutorialStep: Int, CaseIterable {
    case openRoute, assignAircraft, startClock, watch, review, money, inbox, hangar, secondRoute, jobs, level

    /// The rail button to light up.
    var section: GameSection? {
        switch self {
        case .openRoute, .secondRoute: GameSection.map
        case .assignAircraft: GameSection.fleet
        case .review: GameSection.routes
        case .money: GameSection.money
        case .inbox: GameSection.inbox
        case .hangar: GameSection.market
        case .jobs: GameSection.jobs
        case .level: GameSection.money
        case .startClock, .watch: nil
        }
    }

    var highlightsSpeed: Bool { self == .startClock }

    /// A tip the player reads and then presses Next on. The other steps finish when the world shows they were done.
    var needsNext: Bool { [.review, .money, .inbox, .jobs, .level].contains(self) }

    /// A step the player may put off with Later (buying an aircraft needs cash they may not have yet).
    var canPutOff: Bool { self == .hangar || self == .secondRoute }

    /// The tips after the first route, in order.
    static let tour: [TutorialStep] = [.review, .money, .inbox, .hangar, .secondRoute, .jobs, .level]

    /// The same tips where routes from home pay little: jobs come straight after the routes tip, since they are the early money there.
    static let tourJobsEarly: [TutorialStep] = [.review, .jobs, .money, .inbox, .hangar, .secondRoute, .level]

    static func order(jobsEarly: Bool) -> [TutorialStep] { jobsEarly ? tourJobsEarly : tour }
}

enum Tutorial {
    /// How many flights the player watches before the tour.
    static let flightsToWatch = 3
    /// Below this profit a day (the guide's suggestion, after head office) the routes count as thin and jobs are taught early.
    static let thinRoutePerDay = 500.0

    /// The step the player is on, or nil once they have been through all of it. `seen` holds the tips already read or put off.
    static func step(world: World, speed: GameSpeed, seen: Set<TutorialStep>, jobsEarly: Bool = false) -> TutorialStep? {
        if world.routes.isEmpty { return .openRoute }
        // An aircraft away on a job goes back to its route by itself afterwards, so it is not parked.
        let onJob = world.aircraft.contains { $0.jobID != nil }
        if world.routes.allSatisfy({ $0.aircraftIDs.isEmpty }) && !onJob {
            // A route none of the aircraft can fly cannot be given one: back to opening a route they can fly.
            return world.routes.contains { world.fleetCanFly(route: $0) } ? .assignAircraft : .openRoute
        }
        if world.airline.stats.flights < flightsToWatch, !seen.contains(.review) { return speed == .paused ? .startClock : .watch }
        for step in TutorialStep.order(jobsEarly: jobsEarly) where !seen.contains(step) {
            if step == .hangar && world.aircraft.count >= 2 { continue }
            if step == .secondRoute && world.routes.count >= 2 { continue }
            return step
        }
        return nil
    }

    /// A good first route from home for the starting aircraft: the best of the suggested routes that starts at home.
    static func suggestion(world: World) -> (code: String, perDay: Double)? {
        let home = world.airline.home
        guard let idea = world.routeIdeas(limit: 20).first(where: { $0.stops.first == home }), idea.stops.count == 2 else { return nil }
        return (code: idea.stops[1], perDay: idea.profitPerDay)
    }

    /// True when the best first route from home earns little once head office is paid (or there is none): then the guide teaches
    /// jobs right after the routes tip.
    static func routesAreThin(_ suggestion: (code: String, perDay: Double)?) -> Bool {
        guard let suggestion else { return true }
        return suggestion.perDay - Tuning.headOfficePerDay(level: 1) < thinRoutePerDay
    }

    /// What the guide says on each step. Plain words, no jargon.
    static func text(for step: TutorialStep, world: World, suggestion: (code: String, perDay: Double)?, flights: Int) -> String {
        switch step {
        case .openRoute:
            var line = world.routes.isEmpty
                ? "Open your first route. On the Map press New route, then tap two airports, one after the other."
                : "Your aircraft cannot fly the route you opened. Close it under Routes, then open one it can fly: on the Map press New route and tap two airports."
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
            return firstFlights(world.airline.stats)
                + " Routes shows what each route earns a day. Tap a route to see how full the seats are. Planes flying full: raise the fare. Flying empty: lower it or fly less often."
        case .money:
            // The Money screen adds up finished days, so on the first day it still shows nothing.
            let first = world.books.isEmpty ? " Today's flights show there from tomorrow." : ""
            return "Money adds up each day at midnight: what flying earned, then running costs, pilot salaries and base upkeep." + first
                + " A parked aircraft still costs money every day, so keep them flying."
        case .inbox:
            return "When something needs a decision, the clock stops and Inbox says why: a breakdown or a low bank balance. Pick an answer and the clock goes on. Bad weather and deliveries show in Inbox as notices, and the clock keeps going."
        case .hangar:
            return "When you have the cash, buy a second aircraft in Hangar. Pick Fits my airports to see only ones that can land where you fly. Used ones arrive within a day."
        case .secondRoute:
            return "Give the new aircraft its own route. Towns with no road to them pay best. Check the forecast before you open it: a green number means profit."
        case .jobs:
            return "Jobs are one-off flights: medevac, mail and charters. They pay well and have a deadline. Open Routes, then Jobs, and send an aircraft. It leaves its route for the job and goes back by itself afterwards."
        case .level:
            return "Your certificate level is on the Money screen. Earn enough and keep a good reputation to buy the next one: it opens bigger aircraft and bigger airports."
        }
    }

    /// The first payoff: "Your first 3 landings carried 21 people and 1,050 kg of freight and took in $8,100."
    static func firstFlights(_ stats: AirlineStats) -> String {
        let landings = stats.flights == 1 ? "landing" : "landings"
        let people = stats.passengers == 1 ? "1 person" : "\(Format.number(stats.passengers)) people"
        return "Your first \(stats.flights) \(landings) carried \(people) and \(Format.number(stats.cargoKg)) kg of freight and took in \(Format.dollars(stats.revenue))."
    }
}

/// Remembers, per save slot, that a new airline's guide is still running and which tips were read. Saves from before the guide
/// existed never show it.
struct TutorialStore {
    var defaults: UserDefaults = .standard

    private func key(_ slot: Int) -> String { "tutorial.active.\(slot)" }
    private func seenKey(_ slot: Int) -> String { "tutorial.seen.\(slot)" }
    func isActive(slot: Int) -> Bool { defaults.bool(forKey: key(slot)) }
    func setActive(_ on: Bool, slot: Int) {
        defaults.set(on, forKey: key(slot))
        if on { defaults.removeObject(forKey: seenKey(slot)) }
    }

    func seen(slot: Int) -> Set<TutorialStep> {
        Set((defaults.array(forKey: seenKey(slot)) as? [Int] ?? []).compactMap(TutorialStep.init(rawValue:)))
    }

    func setSeen(_ steps: Set<TutorialStep>, slot: Int) { defaults.set(steps.map(\.rawValue).sorted(), forKey: seenKey(slot)) }
}

/// The guide while a game is open: which step it is on, and the Skip and Done buttons.
@MainActor
@Observable
final class TutorialCoach {
    private(set) var active: Bool
    private(set) var step: TutorialStep?
    private(set) var seen: Set<TutorialStep>
    /// Where the first routes pay little, the jobs tip comes right after the routes tip (CoachStrip sets it from the suggestion).
    var jobsEarly = false
    private let slot: Int
    @ObservationIgnored private let store: TutorialStore

    init(slot: Int, store: TutorialStore = TutorialStore()) {
        self.slot = slot
        self.store = store
        active = store.isActive(slot: slot)
        seen = store.seen(slot: slot)
    }

    /// Follows the world. Ends the guide after the last step.
    func update(world: World, speed: GameSpeed) {
        guard active else { step = nil; return }
        step = Tutorial.step(world: world, speed: speed, seen: seen, jobsEarly: jobsEarly)
        if step == nil { finish() }
    }

    /// Next on a tip, or Later on a step that can wait: moves on to the next step.
    func next(world: World, speed: GameSpeed) {
        guard let step else { return }
        seen.insert(step)
        store.setSeen(seen, slot: slot)
        update(world: world, speed: speed)
    }

    func finish() {
        active = false
        step = nil
        store.setActive(false, slot: slot)
    }
}
