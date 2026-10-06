// CoreWorld/Restoration.swift: a bought barn find (RareFinds.swift) arrives as a project. It cannot fly, take a job or join a
// route until the player pays for its restoration, which takes weeks in the hangar (fewer with a hangar or the mechanics' perk).
// The work brings it to near-new condition, includes a heavy check, and puts it in the heritage livery.
// The state is an optional field on Aircraft (`restoration`), so older saves load without it. No random draws here.
import CoreCatalog

// MARK: Restoration
extension Tuning {
    /// The bill as a share of the aircraft's value once restored.
    public static let restorationValueShare = 0.35
    /// Days in the hangar: the base plus a day for every few years of age, up to the most. Halved with a hangar or the mechanics' perk.
    public static let restorationBaseDays = 20
    public static let restorationMaxDays = 40
    public static let restorationYearsPerExtraDay = 3.0
    /// Condition when the work is done.
    public static let restoredCondition = 98.0
}

/// A barn find's restoration. Without `untilMinute` the aircraft waits for the player to start it; with it the work is paid for
/// and ends (or ended) at that minute.
public struct Restoration: Sendable, Hashable, Codable {
    public var untilMinute: Int?

    public init(untilMinute: Int? = nil) { self.untilMinute = untilMinute }
}

extension Aircraft {
    /// A barn find that has not been restored yet: it may not fly.
    public var awaitingRestoration: Bool { restoration != nil && restoration?.untilMinute == nil }
}

public enum Restorations {
    /// What restoring an aircraft of this type and age costs.
    public static func cost(type: AircraftType, ageYears: Double) -> Int {
        let restored = Double(Valuation.value(type: type, ageYears: ageYears, condition: Tuning.restoredCondition))
        return max(1, Int((restored * Tuning.restorationValueShare).rounded()))
    }

    /// Days the work takes, with or without a hangar (or the mechanics' perk).
    public static func days(ageYears: Double, fasterHangar: Bool) -> Int {
        let age = max(0, ageYears)
        let days = min(Tuning.restorationMaxDays, Tuning.restorationBaseDays + Int(age / Tuning.restorationYearsPerExtraDay))
        return fasterHangar ? max(1, days / 2) : days
    }
}

extension World {
    /// What restoring this aircraft costs now (nil if it is not waiting for restoration).
    public func restorationCost(aircraftID: Int) -> Int? {
        guard let plane = aircraft.first(where: { $0.id == aircraftID }), plane.awaitingRestoration, let type = plane.type else { return nil }
        return Restorations.cost(type: type, ageYears: plane.ageYears(atDay: clock.dayIndex))
    }

    /// Days the restoration takes where the aircraft is now (nil if it is not waiting for restoration).
    public func restorationDays(aircraftID: Int) -> Int? {
        guard let plane = aircraft.first(where: { $0.id == aircraftID }), plane.awaitingRestoration else { return nil }
        let faster = hasHangar(at: plane.location) || has(.mechanicsGuild)
        return Restorations.days(ageYears: plane.ageYears(atDay: clock.dayIndex), fasterHangar: faster)
    }

    /// Why the restoration cannot start now (nil if it can).
    public func restorationProblem(aircraftID: Int) -> WorldError? {
        guard let plane = aircraft.first(where: { $0.id == aircraftID }) else { return .unknownAircraft(aircraftID) }
        guard plane.isDelivered else { return .notDelivered }
        guard plane.awaitingRestoration, let cost = restorationCost(aircraftID: aircraftID) else { return .invalidChoice }
        switch plane.status {
        case .idle, .boarding: break
        case .flying, .maintenance, .grounded, .onOrder: return .aircraftBusy
        }
        if plane.jobID != nil { return .aircraftBusy }
        if airline.cash < cost { return .notEnoughCash(needed: cost) }
        return nil
    }

    /// Pays for the restoration and puts the aircraft in the hangar. The work includes a heavy check; the aircraft comes out in
    /// near-new condition and the heritage livery. What was paid counts towards what a dealer will offer for it later.
    public mutating func startRestoration(aircraftID: Int) throws {
        if let problem = restorationProblem(aircraftID: aircraftID) { throw problem }
        guard let i = aircraftIndex(aircraftID), let cost = restorationCost(aircraftID: aircraftID),
              let days = restorationDays(aircraftID: aircraftID) else { throw WorldError.invalidChoice }
        let until = clock.minute + days * GameClock.minutesPerDay
        spendOnInvestment(cost)
        let before = aircraft[i].allRouteIDs
        if !before.isEmpty {
            detachFromAllRoutes(i)
            refreshAutoFrequency(routeIDs: before)
        }
        let livery = RareFinds.heritageLivery(logo: airline.branding.logo)
        aircraft[i].purchasePrice += cost
        aircraft[i].condition = max(aircraft[i].condition, Tuning.restoredCondition)
        aircraft[i].livery = livery
        aircraft[i].restoration = Restoration(untilMinute: until)
        markHeavyCheck(i, until: until)
        aircraft[i].status = .maintenance(until: until)
    }

    /// A barn find that waits for restoration and was put on a route anyway: it leaves its routes and parks.
    /// Called by depart(). True if the aircraft was held.
    mutating func holdUnrestored(_ i: Int) -> Bool {
        guard aircraft[i].awaitingRestoration else { return false }
        // Jobs refuse it (jobProblem); if one got through anyway, give it back first (that may re-attach the old route).
        if aircraft[i].jobID != nil { endJob(aircraftIndex: i) }
        let before = aircraft[i].allRouteIDs
        if !before.isEmpty {
            detachFromAllRoutes(i)
            refreshAutoFrequency(routeIDs: before)
        }
        aircraft[i].status = .idle
        return true
    }
}
