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
                Text("Late and missed departures cost reputation. If the service falls short, it also slips a little each week.")
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
