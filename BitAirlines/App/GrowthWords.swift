import CoreCatalog
import CoreWorld

/// The words for growing out of the bush: selling routes, leaving airports, moving the headquarters, trading in. Plain and specific.
enum GrowthWords {
    /// One line of the news feed for a `.growth` item.
    static func news(_ item: NewsItem) -> String {
        let parts = item.subject.split(separator: ":", maxSplits: 1).map(String.init)
        let what = parts.first ?? ""
        let rest = parts.count > 1 ? parts[1] : ""
        switch what {
        case "sold":
            if item.amount > 0 { return "A local operator took over \(rest) for \(Format.dollars(item.amount))." }
            return "A local operator took over \(rest). It was not making money, so they paid nothing."
        case "left": return "You left \(Place.name(rest)). Routes, base and slots there brought in \(Format.dollars(item.amount))."
        case "hq": return "Your headquarters moved to \(Place.name(rest)) for \(Format.dollars(item.amount)). New aircraft are delivered there."
        default: return item.subject
        }
    }

    /// The confirm text for selling a route.
    static func sellRoute(price: Int) -> String {
        if price > 0 {
            return "A local operator takes over the route and pays \(Format.dollars(price)): about \(Tuning.routeSaleDays) days of its profit over the last week. Its aircraft are parked and free for other work."
        }
        return "It has not made money over the last week, so a local operator takes it over for nothing. Its aircraft are parked and free for other work."
    }

    /// What leaving an airport does, one line per part.
    static func leaveLines(_ plan: LeaveAirportPlan) -> [String] {
        var lines: [String] = []
        let n = plan.routeIDs.count
        if n > 0 { lines.append("\(n) route\(n == 1 ? "" : "s") sold to local operators for \(Format.dollars(plan.routeSale)).") }
        if !plan.facilities.isEmpty {
            let names = plan.facilities.map { Words.name($0).lowercased() }.joined(separator: ", ")
            let share = Int((Tuning.leaveAirportRefundShare * 100).rounded())
            lines.append("Base sold (\(names)) for \(Format.dollars(plan.facilityRefund)), \(share)% of what it cost to build.")
        }
        if plan.slots > 0 { lines.append("\(plan.slots) daily slot\(plan.slots == 1 ? "" : "s") sold back for \(Format.dollars(plan.slotRefund)).") }
        if plan.jobs > 0 { lines.append("\(plan.jobs) job\(plan.jobs == 1 ? "" : "s") to or from here leave the board.") }
        lines.append("Aircraft parked here fly home empty. Those flying to it park there when they land.")
        return lines
    }

    /// "with a DHC-6 Twin Otter you could buy"
    static func buyHint(_ typeID: String) -> String {
        let name = AircraftCatalog.type(typeID)?.displayName ?? typeID
        return "You do not have \(article(name)) \(name) yet. Buy one in the Hangar, new or used."
    }

    /// "a" or "an" before a model name.
    static func article(_ name: String) -> String {
        (name.first.map { "AEIOU".contains($0) } ?? false) ? "an" : "a"
    }
}
