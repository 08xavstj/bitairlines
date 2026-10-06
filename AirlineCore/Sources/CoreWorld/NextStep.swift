// CoreWorld/NextStep.swift: the one thing worth doing next, for the short line on the map ("Twin Otter affordable in 9 days").
// Core gives a code and numbers; the app writes the words (BitAirlines/Features/Game/NextStep.swift).
import CoreCatalog

public enum NextStep: Sendable, Hashable {
    /// No route yet.
    case openFirstRoute
    /// An aircraft is parked with nothing to fly.
    case assignAircraft(aircraftID: Int)
    /// Two or more aircraft share the only route.
    case openSecondRoute
    /// A used aircraft in the hangar fits the home airport and the bank can pay for it now.
    case buyAircraft(typeID: String, price: Int)
    /// The aircraft to save for. `days` is nil while the airline is not making money (no date can be given).
    case saveForAircraft(typeID: String, price: Int, days: Int?)
    /// The airline qualifies for the next certificate level and can pay the fee.
    case buyLevel(level: Int, fee: Int)
    /// The airline qualifies for the next level but the fee is more than the bank holds.
    case saveForLevel(level: Int, fee: Int, days: Int?)
    /// The next level needs more reputation (the whole number to reach).
    case levelNeedsReputation(level: Int, reputation: Int)
    /// The next level needs this much more lifetime revenue.
    case levelNeedsRevenue(level: Int, revenue: Int, days: Int?)
    /// The airline holds the top certificate.
    case topLevel
}

extension Tuning {
    /// Below this many aircraft the next step points at the hangar before the next certificate level.
    public static let nextStepFleetGoal = 3
    /// Cash kept back when judging whether an aircraft is affordable (fuel and wages until it earns).
    public static let nextStepCashReserve = 150_000
    /// Days of results averaged to estimate how long saving takes.
    public static let nextStepProfitDays = 7
    /// Longest wait worth giving as a number of days; beyond it the estimate is left out.
    public static let nextStepMaxDays = 9_999
}

extension World {
    /// The one thing worth doing next. Cheap, but the app still keeps it between ticks (it changes at most a few times a day).
    public var nextStep: NextStep {
        if routes.isEmpty { return .openFirstRoute }
        if let parked = aircraft.first(where: { isParked($0) }) { return .assignAircraft(aircraftID: parked.id) }
        if let r = nextLevelRequirement, Progression.meets(r, airline: airline) {
            if airline.cash >= r.fee { return .buyLevel(level: r.level, fee: r.fee) }
            return .saveForLevel(level: r.level, fee: r.fee, days: daysToSave(r.fee - airline.cash))
        }
        if routes.count == 1 && aircraft.count >= 2 { return .openSecondRoute }
        if aircraft.count < Tuning.nextStepFleetGoal, let step = aircraftStep() { return step }
        guard let r = nextLevelRequirement else { return .topLevel }
        if airline.reputation < r.reputation {
            return .levelNeedsReputation(level: r.level, reputation: Int(r.reputation.rounded(.up)))
        }
        let missing = max(0, r.lifetimeRevenue - airline.stats.revenue)
        return .levelNeedsRevenue(level: r.level, revenue: missing, days: daysToReach(missing, perDay: averageDaily { $0.revenue }))
    }

    /// Delivered, on no route or job, not being restored, and doing nothing.
    func isParked(_ plane: Aircraft) -> Bool {
        guard plane.isDelivered, plane.routeID == nil, plane.jobID == nil, plane.restoration == nil else { return false }
        if case .idle = plane.status { return true }
        return false
    }

    /// The used aircraft to buy now (the most seats the bank can pay for) or else the cheapest to save for.
    /// Only types of the airline's level that can use the home airport, and no barn finds (they need restoring first).
    func aircraftStep() -> NextStep? {
        guard let home = AirportCatalog.airport(airline.home) else { return nil }
        var offers: [(listing: UsedListing, seats: Int)] = []
        for listing in market.listings where listing.rare != .barnFind {
            guard let type = AircraftCatalog.type(listing.typeID), type.level <= airline.level, type.canLand(at: home) else { continue }
            offers.append((listing: listing, seats: type.seats))
        }
        offers.sort { a, b in a.listing.price != b.listing.price ? a.listing.price < b.listing.price : a.listing.id < b.listing.id }
        let spare = airline.cash - Tuning.nextStepCashReserve
        let affordable = offers.filter { $0.listing.price <= spare }
        if let best = affordable.max(by: { a, b in a.seats != b.seats ? a.seats < b.seats : a.listing.price > b.listing.price }) {
            return .buyAircraft(typeID: best.listing.typeID, price: best.listing.price)
        }
        guard let cheapest = offers.first else { return nil }
        let price = cheapest.listing.price
        return .saveForAircraft(typeID: cheapest.listing.typeID, price: price, days: daysToSave(price - spare))
    }

    /// Days of saving at the recent operating result to put by `amount`; nil while the airline is losing money or it would take too long.
    func daysToSave(_ amount: Int) -> Int? {
        daysToReach(amount, perDay: averageDaily { $0.net })
    }

    func daysToReach(_ amount: Int, perDay: Double?) -> Int? {
        guard amount > 0 else { return 0 }
        guard let perDay, perDay > 0 else { return nil }
        let estimate = (Double(amount) / perDay).rounded(.up)
        return estimate <= Double(Tuning.nextStepMaxDays) ? Int(estimate) : nil
    }

    /// The average of a daily figure over the last few finished days; nil before the first midnight.
    func averageDaily(_ figure: (DayBook) -> Int) -> Double? {
        let recent = books.suffix(Tuning.nextStepProfitDays)
        guard !recent.isEmpty else { return nil }
        return Double(recent.reduce(0) { $0 + figure($1) }) / Double(recent.count)
    }
}
