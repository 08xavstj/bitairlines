// CoreWorld/Issue.swift: things that need the player. The game pauses at an issue (depending on the pause policy) until it is resolved.
// Core emits codes and numbers; the app writes the words.

public enum IssueKind: Sendable, Hashable, Codable {
    /// An aircraft failed on the ground and cannot fly until the player picks a repair.
    case breakdown(aircraftID: Int)
    /// Cash has gone below zero.
    case overdraft
    /// The airline qualifies for the next certificate level (it must still be bought).
    case certificateReady(level: Int)
    case delivery(aircraftID: Int)
    case weather(airport: String, untilMinute: Int)
    case bankruptcy
}

public enum IssueChoice: String, Sendable, Hashable, Codable {
    case repairNow, flyInMechanic, waitForParts
    case emergencyLoan, declareBankruptcy
    case acknowledge
}

public struct IssueOption: Sendable, Hashable, Codable {
    public var choice: IssueChoice
    public var costUSD: Int
    /// How many days the aircraft (or the situation) takes to clear.
    public var days: Int
}

public struct Issue: Sendable, Hashable, Codable, Identifiable {
    public var id: Int
    public var kind: IssueKind
    public var raisedMinute: Int
    /// True if the game stops running while this is unresolved (decided from the pause policy when it is raised).
    public var pausesGame: Bool
    public var options: [IssueOption]

    /// Critical issues stop the game under the default policy; the rest are notices.
    public var isCritical: Bool {
        switch kind {
        case .breakdown, .overdraft, .bankruptcy: return true
        case .certificateReady, .delivery, .weather: return false
        }
    }
}

public enum PausePolicy: String, Sendable, Hashable, Codable, CaseIterable {
    /// Never stop; issues wait in the inbox.
    case never
    /// Stop only for problems that need a decision (breakdowns, running out of money).
    case critical
    /// Stop for everything, including deliveries and news.
    case all
}

/// A short feed entry for the inbox and news screens.
public struct NewsItem: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case routeOpened, aircraftDelivered, aircraftSold, certificate, breakdown, weather, loan, permit, milestone
        case perk, fuelBought, jobDone, jobLate, event, baseBuilt, kitFitted, slotBought, rivalRoute, pilotHired, pilotSick, noCrew, scenario
        /// Growing out of the bush (Growth.swift): subject "sold:<route name>", "left:<airport>" or "hq:<airport>"; amount in dollars.
        case growth
        /// A spare aircraft moved to a route that needed it more (FleetBalance.swift): subject the registration, amount the new route's id.
        case fleetMoved

        /// A kind added by a newer version of the game reads as a plain milestone (the subject and amount stay as they were),
        /// so one new kind of news never makes a whole save unreadable on a device that has not updated yet.
        /// Only news does this: game rules (perks, kits, jobs, issues) have no harmless stand-in, so those stay strict.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .milestone
        }
    }
    public var minute: Int
    public var kind: Kind
    /// Free numbers and codes for the app to put in a sentence: an aircraft id, an airport code, an amount.
    public var subject: String
    public var amount: Int
}
