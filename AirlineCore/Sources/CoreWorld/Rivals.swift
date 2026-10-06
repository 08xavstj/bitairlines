// CoreWorld/Rivals.swift: named computer airlines. They fly between the bigger airports, grow a little each month, move into a
// busy route the player has made pay, and answer a fare cut with one of their own. Where one flies the same pair as the player it
// takes a real share of the market, and its fare sets what the player's fare is compared with. There is no sabotage.
import CoreCatalog
import CoreSim

public struct RivalRoute: Sendable, Hashable, Codable {
    public var a: String
    public var b: String
    public var frequency: Double
    /// Their fare relative to the going fare (1.0 is the going fare).
    public var fareLevel: Double
    public var startedDay: Int

    func serves(_ x: String, _ y: String) -> Bool { (a == x && b == y) || (a == y && b == x) }
}

public struct Rival: Sendable, Hashable, Codable, Identifiable {
    public var id: Int
    public var name: String
    public var code: String
    /// Palette indices for their colours.
    public var primary: Int
    public var secondary: Int
    public var home: String
    public var routes: [RivalRoute]
}

/// One row of the rankings table.
public struct RankRow: Sendable, Hashable {
    public var name: String
    public var code: String
    public var isPlayer: Bool
    public var routes: Int
    public var aircraft: Int
    public var passengersPerYear: Int
}

extension World {
    static let rivalNames: [(String, String)] = [
        ("Snowgoose Airways", "SG"), ("Tamarack Air", "TK"), ("Muskeg Express", "MX"), ("Whiskyjack Aviation", "WJ"), ("Ptarmigan Air", "PT"),
        ("Driftwood Airways", "DW"), ("Ironwood Air Lines", "IW"), ("Kestrel Air", "KE"), ("Longsun Airways", "LS"), ("Cobalt Air", "CB"),
        ("Granite Air", "GR"), ("Sandpiper Air", "SP"), ("Bluefin Airways", "BF"), ("Larkspur Air", "LK"),
    ]

    /// Sets up the computer airlines at the start of a game: three near home, two big ones in the home country. None flies from the
    /// player's home at the start.
    mutating func makeRivals() {
        guard let home = AirportCatalog.airport(airline.home) else { return }
        var names = World.rivalNames
        ops.rng.shuffle(&names)
        let big = AirportCatalog.all.filter { ($0.kind == .large || $0.kind == .medium) && $0.code != home.code && $0.population >= 15_000 }
        let near = big.filter { $0.distanceKm(to: home) <= 1500 }.sorted { $0.population > $1.population }
        let national = big.filter { $0.country == home.country }.sorted { $0.population > $1.population }
        var homes: [Airport] = []
        for a in Array(near.prefix(3)) + Array(national.prefix(4)) where !homes.contains(where: { $0.code == a.code }) && homes.count < 5 { homes.append(a) }
        for (n, base) in homes.enumerated() where n < names.count {
            var rival = Rival(id: n + 1, name: names[n].0, code: names[n].1, primary: ops.rng.int(7...27), secondary: ops.rng.int(1...6), home: base.code, routes: [])
            let partners = big.filter { $0.code != base.code && $0.distanceKm(to: base) <= 1500 }.sorted { $0.population > $1.population }
            for partner in partners.prefix(ops.rng.int(3...6)) {
                rival.routes.append(RivalRoute(a: base.code, b: partner.code, frequency: Double(ops.rng.int(1...4)), fareLevel: 1.0, startedDay: 0))
            }
            ops.rivals.append(rival)
        }
    }

    /// Rival routes on a pair of airports.
    func rivalRoutes(_ x: String, _ y: String) -> [RivalRoute] {
        var found: [RivalRoute] = []
        for rival in ops.rivals { for r in rival.routes where r.serves(x, y) { found.append(r) } }
        return found
    }

    /// Once a month: rivals answer fare cuts, drift back to normal fares, open a route, and may move into a busy route of the player's.
    mutating func monthlyRivals() {
        for v in ops.rivals.indices {
            for r in ops.rivals[v].routes.indices {
                let pair = ops.rivals[v].routes[r]
                let ours = routes.filter { route in route.legs.contains { ($0.from == pair.a && $0.to == pair.b) || ($0.from == pair.b && $0.to == pair.a) } }
                if let cheapest = ours.map(\.fareMultiplier).min(), cheapest < pair.fareLevel - 0.1 {
                    ops.rivals[v].routes[r].fareLevel = max(0.75, pair.fareLevel - 0.05)
                } else {
                    ops.rivals[v].routes[r].fareLevel = min(1.0, pair.fareLevel + 0.02)
                }
            }
        }
        guard !ops.rivals.isEmpty else { return }
        let v = ops.rng.int(0...(ops.rivals.count - 1))
        // Move in on a busy, mature route of the player's.
        if ops.rng.chance(Tuning.rivalEntryChance) {
            let busy = routes.filter { clock.dayIndex - $0.openedDay >= 180 && $0.revenueLastMonth > $0.costLastMonth }
                .flatMap { $0.legs }.filter { $0.marketPaxPerDay >= Tuning.rivalEntryPaxPerDay && rivalRoutes($0.from, $0.to).isEmpty }
            if let leg = busy.first {
                ops.rivals[v].routes.append(RivalRoute(a: leg.from, b: leg.to, frequency: 2, fareLevel: 0.95, startedDay: clock.dayIndex))
                addNews(.rivalRoute, subject: ops.rivals[v].code + ":" + leg.from + ":" + leg.to, amount: ops.rivals[v].id)
                return
            }
        }
        // Or grow in its own region.
        if ops.rng.chance(0.3), let base = AirportCatalog.airport(ops.rivals[v].home) {
            let partners = AirportCatalog.all.filter {
                ($0.kind == .large || $0.kind == .medium) && $0.code != base.code && $0.code != airline.home && $0.population >= 15_000
                    && $0.distanceKm(to: base) <= 1500 && !ops.rivals[v].routes.contains(where: { r in r.serves(base.code, $0.code) })
            }.sorted { $0.population > $1.population }
            if let partner = partners.first {
                ops.rivals[v].routes.append(RivalRoute(a: base.code, b: partner.code, frequency: 1, fareLevel: 1.0, startedDay: clock.dayIndex))
            }
        }
    }

    /// The rankings: every airline by passengers a year (rivals estimated from their routes).
    public var rankings: [RankRow] {
        let days = max(30, clock.dayIndex)
        let mine = RankRow(name: airline.name, code: airline.code, isPlayer: true, routes: routes.count, aircraft: aircraft.filter(\.isDelivered).count,
                           passengersPerYear: airline.stats.passengers * 365 / days)
        var rows = [mine]
        for rival in ops.rivals {
            var pax = 0.0
            var seatsFlown = 0.0
            for r in rival.routes {
                guard let a = AirportCatalog.airport(r.a), let b = AirportCatalog.airport(r.b) else { continue }
                let km = a.distanceKm(to: b)
                pax += 2 * 365 * Demand.passengersPerDay(from: a, to: b, distanceKm: km) * Tuning.rivalMarketShare
                seatsFlown += r.frequency * km
            }
            rows.append(RankRow(name: rival.name, code: rival.code, isPlayer: false, routes: rival.routes.count,
                                aircraft: max(1, Int((seatsFlown / 1500).rounded())), passengersPerYear: Int(pax)))
        }
        return rows.sorted { $0.passengersPerYear > $1.passengersPerYear }
    }
}
