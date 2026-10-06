import SwiftUI
import CoreWorld

/// Where reputation stands and what moved it this week: "Reputation 34, falling: 12% of departures late this week."
struct ReputationCard: View {
    let world: World

    var body: some View {
        let trend = world.reputationTrend
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("REPUTATION").pixelFont(13.333).foregroundStyle(Theme.accent)
                    Spacer()
                    Tag(text: ReputationCard.word(trend.direction), color: ReputationCard.color(trend.direction))
                }
                Text(ReputationCard.headline(trend)).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                KeyValueRow("Change " + ReputationCard.period(trend), ReputationCard.signed(trend.change), color: ReputationCard.color(trend.direction))
                if trend.departures > 0 {
                    KeyValueRow("Departures on time", "\(Format.number(trend.departures - trend.late)) of \(Format.number(trend.departures))")
                }
                if let load = trend.load { KeyValueRow("Seats filled", Format.percent(load)) }
                if trend.missed > 0 { KeyValueRow("Departures missed", Format.number(trend.missed), color: Theme.bad) }
                if let blocked = ReputationWords.blockedLine(world) {
                    Text(blocked).pixelFont(10.667).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
                }
                Text("HOW TO RAISE IT").pixelFont(10.667).foregroundStyle(Theme.textPrimary).padding(.top, 2)
                ForEach(ReputationWords.levers, id: \.self) { line in
                    Text(line).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
                Text("If the service falls short, reputation also slips a little each week.")
                    .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func headline(_ trend: ReputationTrend) -> String {
        let start = "Reputation \(Int(trend.reputation)), \(word(trend.direction).lowercased())"
        guard let reason = trend.reasons.first else { return start + "." }
        return start + ": " + explain(reason, trend) + "."
    }

    static func explain(_ reason: ReputationReason, _ trend: ReputationTrend) -> String {
        let when = period(trend)
        switch reason {
        case .goodFlights:
            let full = trend.load.map { ", seats \(Format.percent($0)) full" } ?? ""
            return "\(Format.number(trend.departures)) departures \(when)\(full)"
        case .lateFlights: return "\(Format.percent(trend.lateShare)) of departures late \(when)"
        case .missedFlights:
            return "\(Format.number(trend.missed)) departure\(trend.missed == 1 ? "" : "s") missed \(when) with no aircraft able to fly"
        case .belowStandard: return "slipping towards \(Int(trend.target)) until flights run on time and fuller"
        case .quietWeek: return "nothing flew \(when)"
        case .otherLosses: return "breakdowns and late jobs"
        case .otherGains: return "jobs, events and campaigns"
        }
    }

    static func period(_ trend: ReputationTrend) -> String { trend.isThisWeek ? "this week" : "last week" }

    static func word(_ direction: ReputationDirection) -> String {
        switch direction {
        case .rising: "Rising"
        case .steady: "Steady"
        case .falling: "Falling"
        }
    }

    static func color(_ direction: ReputationDirection) -> Color {
        switch direction {
        case .rising: Theme.good
        case .steady: Theme.textMuted
        case .falling: Theme.bad
        }
    }

    /// Two decimals with a sign: "+0.04", "-1.20".
    static func signed(_ value: Double) -> String {
        let hundredths = Int((value * 100).rounded())
        let sign = hundredths < 0 ? "-" : "+"
        let n = abs(hundredths)
        let cents = n % 100
        return "\(sign)\(n / 100).\(cents < 10 ? "0" : "")\(cents)"
    }
}

/// The words for raising reputation: the reputation card lists every lever, and the places that say a level needs more
/// reputation (the next-step line, the certificate card) can add the short hint.
enum ReputationWords {
    /// Every lever, the biggest first. Campaign numbers come from Tuning, so they follow any rebalance.
    static var levers: [String] {
        [
            "Fly on time. Every late departure costs reputation: give busy routes enough aircraft for their schedule.",
            "Fill the seats and pick better service. Full flights with premium service earn the most.",
            "Keep aircraft flying. A breakdown costs reputation, and so does every departure a route misses while its aircraft are in the hangar. Repair quickly; a hangar at the base makes checks quicker.",
            "Fly jobs on time. A late job costs more than an on-time one earns.",
            "Run a campaign from the Money screen: radio +\(campaign(.radio)), national +\(campaign(.national)).",
        ]
    }

    /// One short hint for lines that only have room for a few words.
    static let shortHint = "Fly on time, fill the seats, take jobs and run campaigns."

    /// "Level 3 needs reputation 22 (now 18)." when reputation holds the next level back; nil otherwise.
    static func blockedLine(_ world: World) -> String? {
        guard let next = world.nextLevelRequirement, world.airline.reputation < next.reputation else { return nil }
        return "Level \(next.level) needs reputation \(Int(next.reputation.rounded(.up))) (now \(Int(world.airline.reputation)))."
    }

    static func campaign(_ c: Campaign) -> Int { Int(Tuning.campaignReputation(c).rounded()) }
}
