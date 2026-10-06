import SwiftUI
import CoreWorld

/// On a route card: what the route made over the last 7 days, and a hint when it lost money.
struct RouteProfitLine: View {
    let route: Route

    var body: some View {
        let week = route.last7Days
        VStack(alignment: .leading, spacing: 3) {
            if week.flights == 0 && week.cost == 0 {
                Text("\(period): no flights.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            } else {
                summary(week).pixelFont(10.667).fixedSize(horizontal: false, vertical: true)
                if let hint = RouteProfitLine.hint(for: week) {
                    Text(hint).pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
                }
                Text("Since opened: \(Format.signedMoney(route.profitSinceOpened)). Costs are the flights and the aircraft. Head office is not included.")
                    .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Last 7 days", or fewer for a route that has not been open that long.
    private var period: String {
        let days = route.book.recentDays
        if days >= Route.bookDays { return "Last 7 days" }
        return days == 1 ? "Today" : "Last \(days) days"
    }

    private func summary(_ week: RouteDay) -> Text {
        let profit = Text("\(Format.signedMoney(week.profit)) \(week.profit >= 0 ? "profit" : "loss")")
            .foregroundStyle(week.profit >= 0 ? Theme.good : Theme.bad)
        var rest = " (revenue \(Format.compactMoney(week.revenue)), costs \(Format.compactMoney(week.cost)))"
        if let load = week.seatLoad { rest += ", seats \(Format.percent(load)) full" }
        return Text("\(Text("\(period): ").foregroundStyle(Theme.textMuted))\(profit)\(Text(rest).foregroundStyle(Theme.textMuted))")
    }

    /// What to try when the route lost money: empty seats mean too many flights or too high a fare; full seats mean the fare or aircraft is wrong.
    static func hint(for week: RouteDay) -> String? {
        guard week.profit < 0, week.flights > 0 else { return nil }
        if let load = week.seatLoad, load < 0.5 { return "Losing money: fly less often, or bring the fare back to the going fare if it is higher." }
        return "Losing money: try a higher fare or a smaller aircraft."
    }
}
