// CoreWorld/Scenarios.swift: short games with a goal and a deadline. A scenario fixes where the airline starts and with what; finish
// early for gold, in good time for silver, by the deadline for bronze.
import CoreCatalog

public enum ScenarioID: String, Sendable, Hashable, Codable, CaseIterable {
    case freezeUp, deltaVillages, airAmbulance, islandHopper, bushToJets, bigCarrier
}

public enum ScenarioGoal: Sendable, Hashable {
    /// Deliver this much freight to airports in a region (country, region code).
    case freightToRegion(country: String, region: String, kg: Int)
    /// Fly routes that serve this many airports within a radius of a centre.
    case serveAirports(near: String, radiusKm: Double, count: Int)
    /// Finish this many jobs of a kind.
    case jobs(kind: JobKind, count: Int)
    /// Have a jet route that made money last month.
    case profitableJetRoute
    /// Reach a certificate level.
    case reachLevel(Int)
}

public enum Medal: String, Sendable, Hashable, Codable, CaseIterable {
    case gold, silver, bronze
}

public struct ScenarioDefinition: Sendable, Hashable, Identifiable {
    public let id: ScenarioID
    public let home: String
    public let starterTypeID: String
    public let difficulty: Difficulty
    public let goal: ScenarioGoal
    public let deadlineDays: Int

    public static let all: [ScenarioDefinition] = [
        ScenarioDefinition(id: .freezeUp, home: "YFB", starterTypeID: "dc3", difficulty: .standard,
                           goal: .freightToRegion(country: "CA", region: "NU", kg: 120_000), deadlineDays: 287),
        ScenarioDefinition(id: .deltaVillages, home: "BET", starterTypeID: "c208", difficulty: .standard,
                           goal: .serveAirports(near: "BET", radiusKm: 250, count: 10), deadlineDays: 365),
        ScenarioDefinition(id: .airAmbulance, home: "YZF", starterTypeID: "c208", difficulty: .standard,
                           goal: .jobs(kind: .medevac, count: 12), deadlineDays: 365),
        ScenarioDefinition(id: .islandHopper, home: "NAN", starterTypeID: "c208", difficulty: .standard,
                           goal: .serveAirports(near: "NAN", radiusKm: 400, count: 6), deadlineDays: 270),
        ScenarioDefinition(id: .bushToJets, home: "YEV", starterTypeID: "c208", difficulty: .standard,
                           goal: .profitableJetRoute, deadlineDays: 5 * 365),
        ScenarioDefinition(id: .bigCarrier, home: "FAI", starterTypeID: "c208", difficulty: .standard,
                           goal: .reachLevel(4), deadlineDays: 6 * 365),
    ]

    public static func definition(_ id: ScenarioID) -> ScenarioDefinition? { all.first { $0.id == id } }
}

public struct ScenarioState: Sendable, Hashable, Codable {
    public var id: ScenarioID
    public var startDay: Int
    public var deadlineDay: Int
    /// 0...1.
    public var progress: Double
    /// Freight counted towards a freight goal, in kilograms.
    public var freightKg: Int
    public var finishedDay: Int?
    public var medal: Medal?
    public var failed: Bool
}

extension World {
    /// Counts freight towards the scenario when it lands in the right region.
    mutating func countScenarioFreight(kg: Int, at code: String) {
        guard kg > 0, var state = ops.scenario, state.finishedDay == nil, !state.failed,
              let def = ScenarioDefinition.definition(state.id), case .freightToRegion(let country, let region, _) = def.goal,
              let airport = AirportCatalog.airport(code), airport.country == country, airport.region == region else { return }
        state.freightKg += kg
        ops.scenario = state
    }

    /// Once a day: how far along is the scenario, and is it won or lost?
    mutating func checkScenario() {
        guard var state = ops.scenario, state.finishedDay == nil, !state.failed, let def = ScenarioDefinition.definition(state.id) else { return }
        state.progress = min(1, scenarioProgress(def.goal, state: state))
        let day = clock.dayIndex
        if state.progress >= 1 {
            state.finishedDay = day
            let used = Double(day - state.startDay) / Double(max(1, state.deadlineDay - state.startDay))
            state.medal = used <= 0.6 ? .gold : (used <= 0.8 ? .silver : .bronze)
            addNews(.scenario, subject: state.medal?.rawValue ?? "", amount: 1)
        } else if day > state.deadlineDay {
            state.failed = true
            addNews(.scenario, subject: "failed", amount: 0)
        }
        ops.scenario = state
    }

    func scenarioProgress(_ goal: ScenarioGoal, state: ScenarioState) -> Double {
        switch goal {
        case .freightToRegion(_, _, let kg):
            return Double(state.freightKg) / Double(max(1, kg))
        case .serveAirports(let near, let radius, let count):
            guard let centre = AirportCatalog.airport(near) else { return 0 }
            let served = Set(routes.filter { !$0.aircraftIDs.isEmpty }.flatMap { $0.stops }).filter { code in
                AirportCatalog.airport(code).map { $0.distanceKm(to: centre) <= radius } ?? false
            }
            return Double(served.count) / Double(max(1, count))
        case .jobs(let kind, let count):
            return Double(ops.jobsDone.filter { $0.kind == kind && $0.day >= state.startDay }.count) / Double(max(1, count))
        case .profitableJetRoute:
            let jetRoute = routes.contains { route in
                route.revenueLastMonth > route.costLastMonth && route.aircraftIDs.contains { id in aircraft.first { $0.id == id }?.type?.engine == .jet }
            }
            return jetRoute ? 1 : 0
        case .reachLevel(let level):
            return airline.level >= level ? 1 : Double(airline.level - 1) / Double(max(1, level - 1))
        }
    }
}
