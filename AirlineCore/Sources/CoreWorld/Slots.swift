// CoreWorld/Slots.swift: busy airports ration departures. At an airport of certificate level 3 or above the airline needs a slot for
// every daily departure it schedules there; small strips are free. Slots are bought once (and can be sold back for half).
// A route scheduled beyond its slots still flies, but only as many departures a day as there are slots; the rest wait for tomorrow.
import CoreCatalog

public struct SlotHolding: Sendable, Hashable, Codable {
    public var airport: String
    /// Departures a day.
    public var daily: Int
}

extension World {
    /// Whether this airport hands out slots (only in Normal and Realism).
    public func needsSlots(_ airport: Airport) -> Bool {
        ops.mode.needsSlots && Progression.requiredLevel(for: airport) >= Tuning.slotAirportLevel
    }

    public func slotsHeld(at code: String) -> Int { ops.slots.first { $0.airport == code }?.daily ?? 0 }

    /// Departures a day the airline's routes schedule from an airport.
    public func slotsScheduled(at code: String) -> Int {
        let total = routes.filter { $0.stops.contains(code) }.reduce(0.0) { $0 + $1.frequency }
        return Int(total.rounded(.up))
    }

    /// Price of one daily slot: dearer at bigger airports.
    public func slotPrice(at airport: Airport) -> Int {
        let tier = max(1, Progression.requiredLevel(for: airport) - Tuning.slotAirportLevel + 1)
        return Tuning.slotBasePrice * tier * tier
    }

    /// Airports on a route where the airline schedules more departures than it holds slots for: (airport, slots still needed).
    public func slotShortfall(route: Route) -> [(airport: String, needed: Int)] {
        route.stops.compactMap { code -> (airport: String, needed: Int)? in
            guard let airport = AirportCatalog.airport(code), needsSlots(airport) else { return nil }
            let missing = slotsScheduled(at: code) - slotsHeld(at: code)
            return missing > 0 ? (airport: code, needed: missing) : nil
        }
    }

    public mutating func buySlots(at code: String, count: Int) throws {
        guard let airport = AirportCatalog.airport(code) else { throw WorldError.unknownAirport(code) }
        guard needsSlots(airport) else { throw WorldError.cannotBuildHere }
        guard count >= 1 else { throw WorldError.invalidAmount }
        let price = slotPrice(at: airport) * count
        guard airline.cash >= price else { throw WorldError.notEnoughCash(needed: price) }
        spendOnOverhead(price)
        if let s = ops.slots.firstIndex(where: { $0.airport == code }) { ops.slots[s].daily += count } else {
            ops.slots.append(SlotHolding(airport: code, daily: count))
            ops.slots.sort { $0.airport < $1.airport }
        }
        addNews(.slotBought, subject: code, amount: count)
    }

    public mutating func sellSlots(at code: String, count: Int) throws {
        guard let airport = AirportCatalog.airport(code), let s = ops.slots.firstIndex(where: { $0.airport == code }) else { throw WorldError.invalidChoice }
        let n = min(count, ops.slots[s].daily)
        guard n >= 1 else { throw WorldError.invalidAmount }
        airline.cash += slotPrice(at: airport) * n / 2
        ops.slots[s].daily -= n
        if ops.slots[s].daily == 0 { ops.slots.remove(at: s) }
    }

    /// True if a departure from this airport would go beyond today's slots (and the flight must wait until tomorrow).
    func outOfSlots(at airport: Airport) -> Bool {
        guard needsSlots(airport) else { return false }
        let used = ops.slotsUsedToday.first { $0.airport == airport.code }?.daily ?? 0
        return used >= slotsHeld(at: airport.code)
    }

    mutating func useSlot(at airport: Airport) {
        guard needsSlots(airport) else { return }
        if let s = ops.slotsUsedToday.firstIndex(where: { $0.airport == airport.code }) { ops.slotsUsedToday[s].daily += 1 } else {
            ops.slotsUsedToday.append(SlotHolding(airport: airport.code, daily: 1))
        }
    }
}
