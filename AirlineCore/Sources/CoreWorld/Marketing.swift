// CoreWorld/Marketing.swift: paid campaigns. Each one makes the airline better known for a while (it wins a bigger share of the
// people who fly) and, right away, makes its routes a little better known. Bigger campaigns cost more and last longer.
import CoreCatalog

public enum Campaign: String, Sendable, Hashable, Codable, CaseIterable {
    /// Posters and the local paper.
    case posters
    /// Radio spots across the region.
    case radio
    /// A national campaign.
    case national
}

public struct ActiveCampaign: Sendable, Hashable, Codable {
    public var kind: Campaign
    /// The campaign runs until the start of this day.
    public var untilDay: Int
}

// MARK: Marketing
extension Tuning {
    /// Price at certificate level 1; each level above adds the same again (a level 3 airline pays three times as much).
    public static func campaignBasePrice(_ c: Campaign) -> Int {
        switch c {
        case .posters: 15_000
        case .radio: 60_000
        case .national: 250_000
        }
    }

    public static func campaignDays(_ c: Campaign) -> Int {
        switch c {
        case .posters: 14
        case .radio: 30
        case .national: 60
        }
    }

    /// Share of the market won while it runs, as a multiplier (campaigns of different kinds stack).
    public static func campaignCaptureBoost(_ c: Campaign) -> Double {
        switch c {
        case .posters: 1.05
        case .radio: 1.10
        case .national: 1.15
        }
    }

    /// How much better known every leg becomes at once (1.0 is fully known).
    public static func campaignAwareness(_ c: Campaign) -> Double {
        switch c {
        case .posters: 0.04
        case .radio: 0.08
        case .national: 0.12
        }
    }

    public static func campaignReputation(_ c: Campaign) -> Double {
        switch c {
        case .posters: 0
        case .radio: 1
        case .national: 3
        }
    }
}

extension World {
    public func campaignPrice(_ c: Campaign) -> Int { Tuning.campaignBasePrice(c) * max(1, airline.level) }

    /// The campaign of this kind that is running, if any.
    public func activeCampaign(_ c: Campaign) -> ActiveCampaign? { ops.campaigns.first { $0.kind == c && $0.untilDay > clock.dayIndex } }

    /// Why this campaign cannot start now (nil if it can).
    public func campaignProblem(_ c: Campaign) -> WorldError? {
        if activeCampaign(c) != nil { return .campaignRunning }
        if routes.isEmpty { return .needsARoute }
        let price = campaignPrice(c)
        if airline.cash < price { return .notEnoughCash(needed: price) }
        return nil
    }

    public mutating func startCampaign(_ c: Campaign) throws {
        if let problem = campaignProblem(c) { throw problem }
        spendOnOverhead(campaignPrice(c))
        ops.campaigns.append(ActiveCampaign(kind: c, untilDay: clock.dayIndex + Tuning.campaignDays(c)))
        let lift = Tuning.campaignAwareness(c)
        for r in routes.indices {
            for l in routes[r].legs.indices { routes[r].legs[l].maturity = min(1.0, routes[r].legs[l].maturity + lift) }
        }
        airline.reputation = min(100, airline.reputation + Tuning.campaignReputation(c))
    }

    /// The share multiplier from the campaigns running today.
    var marketingFactor: Double {
        ops.campaigns.filter { $0.untilDay > clock.dayIndex }.reduce(1.0) { $0 * Tuning.campaignCaptureBoost($1.kind) }
    }

    /// Drops finished campaigns. Called every day.
    mutating func endCampaigns() {
        let today = clock.dayIndex
        ops.campaigns.removeAll { $0.untilDay <= today }
    }
}
