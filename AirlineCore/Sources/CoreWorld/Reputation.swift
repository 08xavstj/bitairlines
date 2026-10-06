// CoreWorld/Reputation.swift: reputation moves both ways. Flights earn it (Flights.swift, Service.swift); late departures,
// departures missed because every aircraft on a route is out of service, and a slow weekly drift down towards what the
// service deserves take it away. The drift only pulls down, so a young airline flying normally gains what it always did.
// Nothing here draws a random number.

/// What moved reputation in a week, as codes; the app writes the words.
public enum ReputationReason: String, Sendable, Hashable, Codable, CaseIterable {
    /// Flights earned reputation (fuller aircraft and better service earn more).
    case goodFlights
    /// Departures left more than a quarter of an hour after their slot.
    case lateFlights
    /// Departures missed because every aircraft on the route was grounded or in the hangar.
    case missedFlights
    /// Reputation is above what the service deserves and slips towards it at the end of the week.
    case belowStandard
    /// The airline flew nothing this week.
    case quietWeek
    /// Breakdowns, late or dropped jobs.
    case otherLosses
    /// Events and marketing campaigns.
    case otherGains
}

public enum ReputationDirection: String, Sendable, Hashable, Codable {
    case rising, steady, falling
}

/// One week of reputation bookkeeping. A new type, always saved whole.
public struct ReputationWeek: Sendable, Hashable, Codable {
    public var startReputation: Double
    /// The on-time record when the week began (see OnTimeRecord); this week's departures are the difference.
    public var onTimeAtStart: Double
    public var lateAtStart: Double
    /// Late departures already charged.
    public var lateCharged = 0
    /// Landings with a load (route flights and job deliveries).
    public var flights = 0
    /// Route flights only: people carried, seats flown and the sum of their service factors.
    public var passengers = 0
    public var seats = 0
    public var routeFlights = 0
    public var serviceSum = 0.0
    public var flightGain = 0.0
    public var lateLoss = 0.0
    public var missed = 0
    public var missedLoss = 0.0
    /// Applied when the week closes (zero or negative).
    public var drift = 0.0
    /// Filled when the week closes.
    public var departures: Int?
    public var late: Int?
    public var target: Double?
    public var endReputation: Double?
}

/// This week and the week before. Lives in Operations (missing from older saves; started on first use).
public struct ReputationBook: Sendable, Hashable, Codable {
    public var thisWeek: ReputationWeek
    public var lastWeek: ReputationWeek?
}

/// What the app shows: where reputation stands and why it moved.
public struct ReputationTrend: Sendable, Hashable {
    public var reputation: Double
    /// Change over the week reported (this week so far, or last week early on a Monday).
    public var change: Double
    public var direction: ReputationDirection
    /// True when the numbers are for the week still running.
    public var isThisWeek: Bool
    public var departures: Int
    public var late: Int
    public var missed: Int
    /// Passengers over seats on route flights (nil when no seats were flown).
    public var load: Double?
    /// The level the weekly drift pulls down to.
    public var target: Double
    /// Biggest first.
    public var reasons: [ReputationReason]

    public var lateShare: Double { departures > 0 ? Double(late) / Double(departures) : 0 }
}

// MARK: Reputation
extension Tuning {
    /// Lost for each departure that leaves late (a flight earns about 0.0007).
    public static let reputationPerLateDeparture = 0.001
    /// Lost for each departure missed because the route had no aircraft able to fly.
    public static let reputationPerMissedDeparture = 0.004
    /// Each week reputation above the target loses this share of the gap.
    public static let reputationDriftShare = 0.02
    /// The target for an airline that flies nothing, or is never on time. Below this there is no drift.
    public static let reputationFloorTarget = 15.0
    /// On-time share (recent weeks) at which punctuality counts for nothing, and at which it counts in full.
    public static let reputationLatePoint = 0.6
    public static let reputationOnTimePoint = 0.95
    /// Comfort = base + perLoad x seat load x service factor, at most 1.
    public static let reputationComfortBase = 0.6
    public static let reputationComfortPerLoad = 0.6
    /// A week's change smaller than this reads as steady.
    public static let reputationSteadyBand = 0.005
}

extension World {
    func freshReputationWeek() -> ReputationWeek {
        ReputationWeek(startReputation: airline.reputation, onTimeAtStart: ops.onTime.onTime, lateAtStart: ops.onTime.late)
    }

    /// Starts the book on first use (new games and older saves alike).
    mutating func ensureReputationBook() {
        guard ops.reputationBook == nil else { return }
        let week = freshReputationWeek()
        ops.reputationBook = ReputationBook(thisWeek: week, lastWeek: nil)
    }

    /// Departures and late departures in a week: counted live for the running week, stored for a closed one.
    func punctuality(of week: ReputationWeek) -> (departures: Int, late: Int) {
        if let d = week.departures, let l = week.late { return (d, l) }
        let late = max(0, Int((ops.onTime.late - week.lateAtStart).rounded()))
        let onTime = max(0, Int((ops.onTime.onTime - week.onTimeAtStart).rounded()))
        return (late + onTime, late)
    }

    /// Charges late departures not charged yet. Called on every landing and when the week closes.
    mutating func settleLateDepartures() {
        ensureReputationBook()
        guard var book = ops.reputationBook else { return }
        let late = punctuality(of: book.thisWeek).late
        let fresh = late - book.thisWeek.lateCharged
        guard fresh > 0 else { return }
        let loss = Double(fresh) * Tuning.reputationPerLateDeparture
        airline.reputation = max(0, airline.reputation - loss)
        book.thisWeek.lateCharged = late
        book.thisWeek.lateLoss += loss
        ops.reputationBook = book
    }

    /// Books a landing with a load. `seats` is nil for a job delivery (only route flights count towards seat load).
    mutating func noteReputationFlight(gain: Double, passengers: Int, seats: Int?, service: ServiceLevel) {
        ensureReputationBook()
        guard var book = ops.reputationBook else { return }
        book.thisWeek.flights += 1
        book.thisWeek.flightGain += gain
        if let seats {
            book.thisWeek.passengers += passengers
            book.thisWeek.seats += seats
            book.thisWeek.routeFlights += 1
            book.thisWeek.serviceSum += service.reputationFactor
        }
        ops.reputationBook = book
    }

    /// Once a day: a route whose aircraft are all grounded or in the hangar misses the day's departures.
    mutating func checkMissedDepartures() {
        var missed = 0
        for route in routes where route.frequency > 0 {
            let planes = aircraft.filter { $0.isDelivered && $0.jobID == nil && $0.allRouteIDs.contains(route.id) }
            guard !planes.isEmpty else { continue }
            let anyAble = planes.contains { plane in
                switch plane.status {
                case .grounded, .maintenance, .onOrder: return false
                case .idle, .boarding, .flying: return true
                }
            }
            if !anyAble { missed += Int((route.frequency * Double(route.legs.count)).rounded(.up)) }
        }
        guard missed > 0 else { return }
        ensureReputationBook()
        guard var book = ops.reputationBook else { return }
        let loss = Double(missed) * Tuning.reputationPerMissedDeparture
        airline.reputation = max(0, airline.reputation - loss)
        book.thisWeek.missed += missed
        book.thisWeek.missedLoss += loss
        ops.reputationBook = book
    }

    /// The level the weekly drift pulls reputation down to: high for a punctual airline with full, well served aircraft.
    func reputationTarget(_ week: ReputationWeek) -> Double {
        let floor = Tuning.reputationFloorTarget
        guard week.flights > 0 else { return floor }
        let span = Tuning.reputationOnTimePoint - Tuning.reputationLatePoint
        let punctual = min(1.0, max(0.0, (ops.onTime.share - Tuning.reputationLatePoint) / span))
        var comfort = 1.0
        if week.seats > 0 && week.routeFlights > 0 {
            let load = Double(week.passengers) / Double(week.seats)
            let service = week.serviceSum / Double(week.routeFlights)
            comfort = min(1.0, max(0.0, Tuning.reputationComfortBase + Tuning.reputationComfortPerLoad * load * service))
        }
        return floor + (100.0 - floor) * punctual * comfort
    }

    /// Ends the week: charges what is left, drifts down towards the target, and keeps the week for the trend.
    /// Called before the on-time record is aged (see OperationsDaily.swift).
    mutating func closeReputationWeek() {
        settleLateDepartures()
        guard var book = ops.reputationBook else { return }
        var week = book.thisWeek
        let counts = punctuality(of: week)
        let target = reputationTarget(week)
        if airline.reputation > target {
            let drift = (airline.reputation - target) * Tuning.reputationDriftShare
            airline.reputation -= drift
            week.drift = -drift
        }
        week.departures = counts.departures
        week.late = counts.late
        week.target = target
        week.endReputation = airline.reputation
        book.lastWeek = week
        ops.reputationBook = book
    }

    /// Starts the next week. Called after the on-time record is aged.
    mutating func openReputationWeek() {
        let week = freshReputationWeek()
        if ops.reputationBook == nil {
            ops.reputationBook = ReputationBook(thisWeek: week, lastWeek: nil)
        } else {
            ops.reputationBook?.thisWeek = week
        }
    }

    /// Where reputation stands and what moved it: this week so far, or last week if nothing has flown yet this week.
    public var reputationTrend: ReputationTrend {
        let book = ops.reputationBook
        let current = book?.thisWeek ?? freshReputationWeek()
        var week = current
        var isThisWeek = true
        if let last = book?.lastWeek, current.flights == 0, punctuality(of: current).departures == 0, current.missed == 0 {
            week = last
            isThisWeek = false
        }
        let counts = punctuality(of: week)
        let end = week.endReputation ?? airline.reputation
        let change = end - week.startReputation
        let target = week.target ?? reputationTarget(week)
        let load: Double? = week.seats > 0 ? Double(week.passengers) / Double(week.seats) : nil

        // Each cause with its size; whatever is left over came from breakdowns, jobs, events or campaigns.
        let pendingDrift = isThisWeek && airline.reputation > target ? (airline.reputation - target) * Tuning.reputationDriftShare : 0
        let drift = isThisWeek ? pendingDrift : -week.drift
        let known = week.flightGain - week.lateLoss - week.missedLoss + week.drift
        let other = change - known
        var sized: [(ReputationReason, Double)] = [
            (.goodFlights, week.flightGain),
            (.lateFlights, week.lateLoss),
            (.missedFlights, week.missedLoss),
            (.belowStandard, drift),
            (.otherLosses, max(0, -other)),
            (.otherGains, max(0, other)),
        ]
        if week.flights == 0 && counts.departures == 0 { sized.append((.quietWeek, 1.0)) }
        let order = ReputationReason.allCases
        let reasons = sized.filter { $0.1 > 0.0001 }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return (order.firstIndex(of: a.0) ?? 0) < (order.firstIndex(of: b.0) ?? 0)
            }
            .map { $0.0 }

        let band = Tuning.reputationSteadyBand
        let direction: ReputationDirection = change > band ? .rising : (change < -band ? .falling : .steady)
        return ReputationTrend(reputation: airline.reputation, change: change, direction: direction, isThisWeek: isThisWeek,
                               departures: counts.departures, late: counts.late, missed: week.missed, load: load, target: target, reasons: reasons)
    }
}
