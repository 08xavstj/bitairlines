// CoreWorld/Staff.swift: people the airline can hire to run things for it. Each has a monthly salary and takes one chore off
// the player: fares, breakdowns, or keeping the fleet busy and the schedules right.
import CoreCatalog

public enum StaffRole: String, Sendable, Hashable, Codable, CaseIterable {
    /// Every Monday moves each route's fare towards full but not overflowing aircraft.
    case revenueManager
    /// Settles breakdowns at once with the quickest repair the airline can pay for, so the game does not stop for them.
    case operationsManager
    /// Every Monday moves aircraft a route does not need to routes where they earn more (the route keeps enough), puts parked
    /// aircraft on the route they suit best and resets schedules to the suggested ones.
    case fleetPlanner
}

// MARK: Staff
extension Tuning {
    /// Monthly salary at certificate level 1; it grows by half again for each level above.
    public static func staffBaseSalary(_ role: StaffRole) -> Int {
        switch role {
        case .revenueManager: 3_000
        case .operationsManager: 3_500
        case .fleetPlanner: 4_000
        }
    }

    /// Seats-full share above which the revenue manager raises the fare, and below which it brings a fare above the going fare back down.
    public static let fareRaiseLoad = 0.87
    public static let fareCutLoad = 0.75
    public static let fareStep = 0.05
    /// The revenue manager keeps fares inside these multipliers.
    public static let managedFareRange: ClosedRange<Double> = 0.7...1.6
}

extension World {
    public func hasStaff(_ role: StaffRole) -> Bool { ops.staff.contains(role) }

    public func staffSalary(_ role: StaffRole) -> Int {
        Tuning.staffBaseSalary(role) * (2 + max(1, airline.level) - 1) / 2
    }

    /// What the hired staff cost each month.
    public var staffPayroll: Int { ops.staff.reduce(0) { $0 + staffSalary($1) } }

    public mutating func hire(_ role: StaffRole) throws {
        if hasStaff(role) { throw WorldError.alreadyHired }
        ops.staff.append(role)
        ops.staff.sort { $0.rawValue < $1.rawValue }
    }

    public mutating func dismiss(_ role: StaffRole) throws {
        guard hasStaff(role) else { throw WorldError.notHired }
        ops.staff.removeAll { $0 == role }
    }

    /// The staff's Monday work.
    mutating func weeklyStaff() {
        if hasStaff(.revenueManager) { manageFares() }
        if hasStaff(.fleetPlanner) {
            balanceFleet()
            planFleet()
        }
    }

    /// The fare people compare with on this route: 1.0, or the cheapest rival fare on any of its legs.
    public func goingFare(for route: Route) -> Double {
        var going = 1.0
        for leg in route.legs {
            for rival in rivalRoutes(leg.from, leg.to) { going = min(going, rival.fareLevel) }
        }
        return going
    }

    /// Moves each fare towards the one that earns most (see FareDemand): up while the route flies full; otherwise towards the going fare,
    /// because a cut below it wins fewer people than it costs, and a fare above it on a route with spare seats loses more people than it gains.
    mutating func manageFares() {
        for r in routes.indices {
            guard let load = routes[r].seatLoadLast7Days else { continue }
            let going = (goingFare(for: routes[r]) * 100).rounded() / 100
            var fare = routes[r].fareMultiplier
            if load > Tuning.fareRaiseLoad {
                fare += Tuning.fareStep
            } else if fare < going {
                fare = min(going, fare + Tuning.fareStep)
            } else if fare > going && load < Tuning.fareCutLoad {
                fare = max(going, fare - Tuning.fareStep)
            }
            routes[r].fareMultiplier = min(Tuning.managedFareRange.upperBound, max(Tuning.managedFareRange.lowerBound, (fare * 100).rounded() / 100))
        }
    }

    /// Puts each parked aircraft on the route where it would earn the most, then resets every schedule to the suggested one.
    mutating func planFleet() {
        for i in aircraft.indices {
            guard aircraft[i].isDelivered, aircraft[i].routeID == nil, aircraft[i].jobID == nil, case .idle = aircraft[i].status,
                  let type = aircraft[i].type else { continue }
            var best: (id: Int, perDay: Double)?
            for route in routes where fitProblem(type: type, route: route, kits: aircraft[i].kits) == nil {
                let f = forecast(route: route, type: type, aircraftCount: route.aircraftIDs.count + 1, suggestedSchedule: true)
                if f.isViable, f.profitPerDay > (best?.perDay ?? 0) { best = (route.id, f.profitPerDay) }
            }
            if let best { try? assign(aircraftID: aircraft[i].id, toRoute: best.id) }
        }
        for route in routes where !route.aircraftIDs.isEmpty { try? applySuggestedFrequency(routeID: route.id) }
    }

    /// The operations manager's answer to a breakdown: the quickest repair there is cash for.
    mutating func settleBreakdown(issueID: Int) {
        guard hasStaff(.operationsManager), let issue = issues.first(where: { $0.id == issueID }) else { return }
        let affordable = issue.options.filter { $0.costUSD <= max(0, airline.cash) }
        guard let pick = affordable.min(by: { ($0.days, $0.costUSD) < ($1.days, $1.costUSD) }) else { return }
        try? resolve(issueID: issueID, choice: pick.choice)
    }
}
