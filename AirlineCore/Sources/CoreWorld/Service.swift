// CoreWorld/Service.swift: how well the airline looks after people (per route) and how punctual it is (airline wide).
// Both feed reputation; service also changes how many people choose the route and what each one costs.

public enum ServiceLevel: String, Sendable, Hashable, Codable, CaseIterable {
    /// Coffee from a flask. Cheaper, a few people go elsewhere.
    case basic
    case standard
    /// Hot snacks, newspapers, help with bags. Costs more, wins people and reputation.
    case premium

    /// Share of the market won, relative to standard.
    public var captureFactor: Double {
        switch self {
        case .basic: 0.94
        case .standard: 1.0
        case .premium: 1.06
        }
    }

    /// Extra cost per passenger in dollars, relative to standard.
    public var costPerPassenger: Double {
        switch self {
        case .basic: -5
        case .standard: 0
        case .premium: 9
        }
    }

    /// Reputation earned per flight, relative to standard.
    public var reputationFactor: Double {
        switch self {
        case .basic: 0.8
        case .standard: 1.0
        case .premium: 1.3
        }
    }
}

/// Departures that left within a quarter of an hour of their slot, and those that did not. Older weeks count for less.
public struct OnTimeRecord: Sendable, Hashable, Codable {
    public var onTime: Double = 0
    public var late: Double = 0

    public init() {}

    /// Share of departures on time (1 when there have been none).
    public var share: Double { onTime + late > 0 ? onTime / (onTime + late) : 1.0 }

    public static let graceMinutes = 15
    /// Each week the record keeps this share of what came before.
    public static let weeklyKeep = 0.85
}

extension Route {
    public var service: ServiceLevel {
        get { serviceStore ?? .standard }
        set { serviceStore = newValue }
    }
}

extension World {
    public mutating func setService(routeID: Int, level: ServiceLevel) throws {
        guard let r = routeIndex(routeID) else { throw WorldError.unknownRoute(routeID) }
        routes[r].service = level
    }

    mutating func recordDeparture(scheduled: Int) {
        if clock.minute - scheduled <= OnTimeRecord.graceMinutes { ops.onTime.onTime += 1 } else { ops.onTime.late += 1 }
    }

    /// Reputation earned by one flight: more for a full aircraft, good service and a punctual airline.
    func reputationGain(passengers: Int, seats: Int, service: ServiceLevel) -> Double {
        let load = Double(passengers) / Double(max(1, seats))
        return 0.0004 * (1.0 + load) * service.reputationFactor * reputationFactor * (0.6 + 0.4 * ops.onTime.share)
    }
}
