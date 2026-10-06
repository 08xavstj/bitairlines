// CoreWorld/Events.swift: things that happen in the world near the network. Some change demand for a while (an early thaw closes the
// ice road, a mine opens), some close airports (volcanic ash), some put special jobs on the board (a fire evacuation, a film crew),
// some come with an offer to say yes or no to (sponsoring the winter games), and an oil shock moves the fuel price.
import CoreCatalog
import CoreSim

public enum EventKind: String, Sendable, Hashable, Codable, CaseIterable {
    case forestFire, earlyThaw, volcanicAsh, filmCrew, winterGames, oilShock, miningBoom
}

/// An event that is changing the world right now, around one airport.
public struct ActiveEvent: Sendable, Hashable, Codable, Identifiable {
    public var id: Int
    public var kind: EventKind
    public var airport: String
    public var radiusKm: Double
    /// Multiplies passenger demand to and from airports in reach.
    public var passengerFactor: Double
    /// Multiplies freight demand to airports in reach.
    public var cargoFactor: Double
    public var untilMinute: Int
}

/// A yes-or-no offer that came with an event.
public struct EventOffer: Sendable, Hashable, Codable, Identifiable {
    public var id: Int
    public var kind: EventKind
    public var airport: String
    public var costUSD: Int
    public var reputation: Double
    public var expiresMinute: Int
}

extension World {
    /// Once a week, maybe something happens.
    mutating func weeklyEvents() {
        let now = clock.minute
        ops.events.removeAll { $0.untilMinute <= now }
        ops.offers.removeAll { $0.expiresMinute <= now }
        guard ops.rng.chance(Tuning.eventChancePerWeek), !ops.jobArea.isEmpty else { return }
        let kinds = EventKind.allCases
        let weights = kinds.map { eventWeight($0, month: clock.date.month) }
        let kind = kinds[ops.rng.weightedIndex(weights)]
        let place = ops.jobArea[ops.rng.int(0...(ops.jobArea.count - 1))]
        startEvent(kind, at: place)
    }

    /// How likely each kind of event is in a month: fires in summer, the thaw in spring, the games in winter, oil shocks rarely.
    func eventWeight(_ kind: EventKind, month: Int) -> Double {
        switch kind {
        case .forestFire: (6...8).contains(month) ? 1.5 : ((5...9).contains(month) ? 0.6 : 0)
        case .earlyThaw: (3...5).contains(month) ? 1.5 : 0
        case .volcanicAsh: 0.3
        case .filmCrew: 0.7
        case .winterGames: month == 12 || month <= 3 ? 0.6 : 0
        case .oilShock: 0.15
        case .miningBoom: 0.5
        }
    }

    /// Starts an event of a kind around an airport (the weekly roll does this; public for screenshots and tests).
    public mutating func startEvent(_ kind: EventKind, at place: String) {
        let id = ops.nextEventID
        ops.nextEventID += 1
        let day = GameClock.minutesPerDay
        switch kind {
        case .forestFire:
            for _ in 0..<ops.rng.int(2...4) {
                if let job = makeJob(kind: .evacuation, near: place) { ops.jobs.append(job) }
            }
        case .earlyThaw:
            ops.events.append(ActiveEvent(id: id, kind: kind, airport: place, radiusKm: 400, passengerFactor: 1.0, cargoFactor: 2.0, untilMinute: clock.minute + 30 * day))
        case .volcanicAsh:
            guard ops.mode.hasWeather, let centre = AirportCatalog.airport(place) else { return }
            let until = clock.minute + ops.rng.int(2...4) * day
            for code in ops.jobArea {
                guard let a = AirportCatalog.airport(code), a.distanceKm(to: centre) <= 500, !market.closures.contains(where: { $0.airport == code }) else { continue }
                market.closures.append(Closure(airport: code, untilMinute: until))
            }
        case .filmCrew:
            if let job = makeJob(kind: .filmCrew, near: place) { ops.jobs.append(job) }
        case .winterGames:
            ops.events.append(ActiveEvent(id: id, kind: kind, airport: place, radiusKm: 50, passengerFactor: 1.6, cargoFactor: 1.2, untilMinute: clock.minute + 14 * day))
            ops.offers.append(EventOffer(id: id, kind: kind, airport: place, costUSD: 40_000 * airline.level, reputation: 3, expiresMinute: clock.minute + 7 * day))
        case .oilShock:
            market.fuelIndex = min(2.4, market.fuelIndex * 1.25)
        case .miningBoom:
            ops.events.append(ActiveEvent(id: id, kind: kind, airport: place, radiusKm: 150, passengerFactor: 1.4, cargoFactor: 1.6, untilMinute: clock.minute + 180 * day))
        }
        addNews(.event, subject: place, amount: EventKind.allCases.firstIndex(of: kind) ?? 0)
    }

    /// How much events are lifting demand on a leg right now (1 when nothing is going on).
    func eventFactors(from a: Airport, to b: Airport) -> (passengers: Double, cargo: Double) {
        var pax = 1.0
        var cargo = 1.0
        for event in ops.events where event.untilMinute > clock.minute {
            guard let centre = AirportCatalog.airport(event.airport) else { continue }
            let nearA = a.distanceKm(to: centre) <= event.radiusKm
            let nearB = b.distanceKm(to: centre) <= event.radiusKm
            if nearA || nearB { pax *= event.passengerFactor }
            if nearB { cargo *= event.cargoFactor }
        }
        return (pax, cargo)
    }

    /// Says yes to an offer: pay, and earn the reputation.
    public mutating func acceptOffer(id: Int) throws {
        guard let o = ops.offers.firstIndex(where: { $0.id == id }) else { throw WorldError.invalidChoice }
        let offer = ops.offers[o]
        guard airline.cash >= offer.costUSD else { throw WorldError.notEnoughCash(needed: offer.costUSD) }
        spendOnOverhead(offer.costUSD)
        airline.reputation = min(100, airline.reputation + offer.reputation)
        ops.offers.remove(at: o)
    }

    public mutating func declineOffer(id: Int) throws {
        guard let o = ops.offers.firstIndex(where: { $0.id == id }) else { throw WorldError.invalidChoice }
        ops.offers.remove(at: o)
    }
}
