// CoreWorld/SlotNeeds.swift: the slots a planned route would still have to buy before its flights can leave, so route ideas
// (RouteIdeas.swift) and forecasts can count the bill before the route opens. With no slot held at an airport, a flight there
// never leaves (Slots.swift: outOfSlots), so this is part of what the route costs. Codes and numbers only; no random draws.
import CoreCatalog

/// Daily slots a planned route would still need at one airport, and what they cost there.
public struct SlotNeed: Sendable, Hashable {
    public var airport: String
    /// Departures a day still to buy.
    public var slots: Int
    /// What they cost at today's price.
    public var cost: Int
    /// True when the airline holds no slot there yet: until it buys some, no flight leaves that airport.
    public var noneHeld: Bool
}

extension World {
    /// The slots a new route through `stops` would still need at `frequency` departures a day, airport by airport in stop order.
    /// Slots the airline holds and its other routes do not use count first. Empty where no airport hands out slots.
    public func slotNeeds(stops: [String], frequency: Double) -> [SlotNeed] {
        var needs: [SlotNeed] = []
        var seen: [String] = []
        for code in stops where !seen.contains(code) {
            seen.append(code)
            guard let airport = AirportCatalog.airport(code), needsSlots(airport) else { continue }
            let scheduled = routes.filter { $0.stops.contains(code) }.reduce(0.0) { $0 + $1.frequency }
            let usedNow = Int(scheduled.rounded(.up))
            let after = Int((scheduled + max(0.0, frequency)).rounded(.up))
            let held = slotsHeld(at: code)
            let missing = after - max(usedNow, held)
            if missing > 0 {
                needs.append(SlotNeed(airport: code, slots: missing, cost: missing * slotPrice(at: airport), noneHeld: held == 0))
            }
        }
        return needs
    }

    /// What the slots a new route would still need cost in all (0 where none are needed). For the forecast: add it to the
    /// investment of a route that does not exist yet.
    public func slotCost(stops: [String], frequency: Double) -> Int {
        slotNeeds(stops: stops, frequency: frequency).reduce(0) { $0 + $1.cost }
    }

    /// The slots an open route's airports are short of today (from `slotShortfall`), with their cost.
    public func slotNeeds(route: Route) -> [SlotNeed] {
        slotShortfall(route: route).compactMap { item -> SlotNeed? in
            guard let airport = AirportCatalog.airport(item.airport) else { return nil }
            return SlotNeed(airport: item.airport, slots: item.needed, cost: item.needed * slotPrice(at: airport), noneHeld: slotsHeld(at: item.airport) == 0)
        }
    }
}
