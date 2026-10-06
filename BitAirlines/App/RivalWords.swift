import CoreCatalog
import CoreWorld

/// The words for rival airlines: their news items and the notes under a route they share with the player.
/// Core sends codes only. A rival news subject is "CODE:A:B" (moved in), or "cut:", "more:" or "left:" followed by "CODE:A:B".
enum RivalWords {
    static func news(_ item: NewsItem, world: World) -> String {
        let parts = item.subject.split(separator: ":").map(String.init)
        let rival = world.ops.rivals.first { $0.id == item.amount }?.name ?? "A rival airline"
        if parts.count == 4 {
            let pair = "\(Place.name(parts[2])) to \(Place.name(parts[3]))"
            switch parts[0] {
            case "cut": return "\(rival) cut its fares on \(pair). A fare war has started."
            case "more": return "\(rival) added flights on \(pair) to win passengers from you."
            case "left": return "\(rival) gave up on \(pair). The route is yours."
            default: return "\(rival) changed its schedule on \(pair)."
            }
        }
        if parts.count == 3 { return "\(rival) now flies \(Place.name(parts[1])) to \(Place.name(parts[2])), against you." }
        return "\(rival) opened a new route."
    }

    /// Lines about one rival on one of the player's legs.
    static func routeLines(rival: Rival, route: RivalRoute, from: String, to: String) -> [String] {
        let fare = Int((route.fareLevel * 100).rounded())
        var lines = ["\(rival.name) also flies \(Place.name(from)) to \(Place.name(to)), \(Format.oneDecimal(route.frequency)) a day at \(fare)% of the going fare."]
        if route.isCuttingFares { lines.append("\(rival.name) cut fares on this route.") }
        if route.addedFlights > 0 { lines.append("\(rival.name) added flights on this route.") }
        if route.weeksLosing > 0 { lines.append("\(rival.name) is losing passengers to you here. Keep it up and they may pull out.") }
        return lines
    }
}
