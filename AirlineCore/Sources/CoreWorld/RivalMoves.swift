// CoreWorld/RivalMoves.swift: how rival airlines fight back. Once a week, from certificate level 2, a rival that shares a pair with
// one of the player's most profitable routes may cut its fare (a fare war) or add flights (a bigger share of the market). A rival the
// player beats on both frequency and fare for several weeks pulls out of the pair. Rivals also grow with the player's level, but only
// between airports with a real market, and they keep out of remote fly-in towns. All draws come from `ops.rng`.
// News subjects (kind .rivalRoute, amount = rival id): "CODE:A:B" moved in, "cut:CODE:A:B", "more:CODE:A:B", "left:CODE:A:B".
import CoreCatalog
import CoreSim

extension Tuning {
    /// Chance each month that a rival moves into one of the player's busy routes.
    public static let rivalMoveInChance = 0.3
    /// Rivals stay out of a market where either end is more remote than this (Demand.isolation, 0 to 1).
    public static let rivalRemoteIsolation = 0.5
    /// Rivals fight back from this certificate level up.
    public static let rivalAnswerLevel = 2
    /// How many of the player's most profitable routes rivals watch.
    public static let rivalAnswerTopRoutes = 3
    /// Weekly chance that a rival on one of those routes answers.
    public static let rivalAnswerChance = 0.25
    /// Days a rival waits between two answers on the same pair.
    public static let rivalAnswerCooldownDays = 28
    /// One fare cut, and the lowest fare a rival will go to (relative to the going fare).
    public static let rivalFareCut = 0.08
    public static let rivalFareFloor = 0.7
    /// Flights a day a rival adds in one answer, and at most on one pair.
    public static let rivalFlightStep = 1.0
    public static let rivalAddedFlightsMax = 4.0
    /// Each added rival flight a day makes the market this much more contested, up to the maximum.
    public static let rivalIntensityPerAddedFlight = 0.05
    public static let rivalIntensityMax = 0.6
    /// Weeks in a row a rival must be beaten on a pair before it pulls out.
    public static let rivalLeaveWeeks = 8
    /// Monthly growth: base chance and extra per certificate level above 1.
    public static let rivalGrowthChance = 0.3
    public static let rivalGrowthChancePerLevel = 0.08
    /// How far from its home a rival opens routes, and how much further per level above 1.
    public static let rivalReachKm = 1500.0
    public static let rivalReachKmPerLevel = 250.0
    /// Most routes one rival flies: base plus this many per player level.
    public static let rivalRoutesBase = 6
    public static let rivalRoutesPerLevel = 2
    /// A new rival route needs at least this many people a day each way.
    public static let rivalGrowthPaxPerDay = 40.0
}

extension World {
    /// How contested a market is where these rival routes fly it: added rival flights push it up.
    func rivalPressure(_ rivals: [RivalRoute]) -> Double {
        let added = rivals.reduce(0.0) { $0 + $1.addedFlights }
        return min(Tuning.rivalIntensityMax, Tuning.rivalIntensity + Tuning.rivalIntensityPerAddedFlight * added)
    }

    /// The player's routes that fly a leg between these two airports.
    func playerRoutes(_ x: String, _ y: String) -> [Route] {
        routes.filter { route in route.legs.contains { ($0.from == x && $0.to == y) || ($0.from == y && $0.to == x) } }
    }

    /// Ids of the player's most profitable routes last month (profit first, then id).
    func rivalTargets() -> [Int] {
        let paying = routes.filter { $0.revenueLastMonth > $0.costLastMonth }
        let sorted = paying.sorted { lhs, rhs in
            let p = lhs.revenueLastMonth - lhs.costLastMonth, q = rhs.revenueLastMonth - rhs.costLastMonth
            return p != q ? p > q : lhs.id < rhs.id
        }
        return sorted.prefix(Tuning.rivalAnswerTopRoutes).map(\.id)
    }

    /// True for a market rivals leave alone: a remote fly-in town at either end.
    func isRemoteMarket(_ x: String, _ y: String) -> Bool {
        guard let a = AirportCatalog.airport(x), let b = AirportCatalog.airport(y) else { return true }
        return max(Demand.isolation(a), Demand.isolation(b)) > Tuning.rivalRemoteIsolation
    }

    /// Legs of busy, mature, paying routes a rival could move into, busiest first.
    func rivalEntryLegs() -> [LegState] {
        let today = clock.dayIndex
        let mature = routes.filter { today - $0.openedDay >= 180 && $0.revenueLastMonth > $0.costLastMonth }
        let legs = mature.flatMap(\.legs).filter {
            $0.marketPaxPerDay >= Tuning.rivalEntryPaxPerDay && rivalRoutes($0.from, $0.to).isEmpty && !isRemoteMarket($0.from, $0.to)
        }
        return legs.sorted { lhs, rhs in
            lhs.marketPaxPerDay != rhs.marketPaxPerDay ? lhs.marketPaxPerDay > rhs.marketPaxPerDay : lhs.from + lhs.to < rhs.from + rhs.to
        }
    }

    /// Once a week: rivals keep score on shared pairs, answer on the player's best routes, and pull out of pairs they have lost.
    mutating func weeklyRivals() {
        guard !ops.rivals.isEmpty else { return }
        let targets = rivalTargets()
        let today = clock.dayIndex
        var leaving: [(rival: Int, route: Int)] = []
        for v in ops.rivals.indices {
            for r in ops.rivals[v].routes.indices {
                let pair = ops.rivals[v].routes[r]
                let mine = playerRoutes(pair.a, pair.b)
                guard !mine.isEmpty else {
                    ops.rivals[v].routes[r].weeksLosing = 0
                    continue
                }
                // Keeping score: beaten when the player flies more often and no dearer.
                let myFrequency = mine.reduce(0.0) { $0 + $1.frequency }
                let myFare = mine.map(\.fareMultiplier).min() ?? 1.0
                let beaten = myFrequency > pair.frequency && myFare <= pair.fareLevel
                let losing = beaten ? pair.weeksLosing + 1 : 0
                ops.rivals[v].routes[r].weeksLosing = losing
                if losing >= Tuning.rivalLeaveWeeks {
                    leaving.append((rival: v, route: r))
                    continue
                }
                // Answering on one of the player's best routes.
                guard airline.level >= Tuning.rivalAnswerLevel, mine.contains(where: { targets.contains($0.id) }) else { continue }
                if let last = pair.lastMoveDay, today - last < Tuning.rivalAnswerCooldownDays { continue }
                let canAdd = pair.addedFlights < Tuning.rivalAddedFlightsMax
                let canCut = pair.fareLevel > Tuning.rivalFareFloor + 0.001
                guard canAdd || canCut, ops.rng.chance(Tuning.rivalAnswerChance) else { continue }
                var addFlights = canAdd
                if canAdd && canCut { addFlights = ops.rng.chance(0.5) }
                let code = ops.rivals[v].code
                let id = ops.rivals[v].id
                if addFlights {
                    ops.rivals[v].routes[r].frequency = pair.frequency + Tuning.rivalFlightStep
                    ops.rivals[v].routes[r].addedFlights = pair.addedFlights + Tuning.rivalFlightStep
                    addNews(.rivalRoute, subject: "more:" + code + ":" + pair.a + ":" + pair.b, amount: id)
                } else {
                    ops.rivals[v].routes[r].fareLevel = max(Tuning.rivalFareFloor, pair.fareLevel - Tuning.rivalFareCut)
                    addNews(.rivalRoute, subject: "cut:" + code + ":" + pair.a + ":" + pair.b, amount: id)
                }
                ops.rivals[v].routes[r].lastMoveDay = today
            }
        }
        // Pull out of lost pairs, last first so the indices stay right.
        let ordered = leaving.sorted { $0.rival != $1.rival ? $0.rival > $1.rival : $0.route > $1.route }
        for item in ordered {
            let pair = ops.rivals[item.rival].routes[item.route]
            let code = ops.rivals[item.rival].code
            let id = ops.rivals[item.rival].id
            ops.rivals[item.rival].routes.remove(at: item.route)
            addNews(.rivalRoute, subject: "left:" + code + ":" + pair.a + ":" + pair.b, amount: id)
        }
    }

    /// Monthly growth. More attempts, a better chance, a longer reach and more routes per rival as the player's level rises.
    mutating func growRivals(first: Int) {
        guard !ops.rivals.isEmpty else { return }
        let level = max(1, airline.level)
        let attempts = 1 + level / 3
        let chance = min(0.9, Tuning.rivalGrowthChance + Tuning.rivalGrowthChancePerLevel * Double(level - 1))
        let cap = Tuning.rivalRoutesBase + Tuning.rivalRoutesPerLevel * level
        for n in 0..<attempts {
            let v = n == 0 ? first : ops.rng.int(0...(ops.rivals.count - 1))
            guard v < ops.rivals.count, ops.rng.chance(chance) else { continue }
            guard ops.rivals[v].routes.count < cap, let route = rivalNewRoute(for: v, level: level) else { continue }
            ops.rivals[v].routes.append(route)
        }
    }

    /// The biggest market from a rival's home it does not fly yet, within reach and busy enough; nil if none.
    func rivalNewRoute(for v: Int, level: Int) -> RivalRoute? {
        guard let base = AirportCatalog.airport(ops.rivals[v].home) else { return nil }
        let flown = ops.rivals[v].routes
        let home = airline.home
        let reach = Tuning.rivalReachKm + Tuning.rivalReachKmPerLevel * Double(level - 1)
        let partners = AirportCatalog.all.filter { candidate in
            guard candidate.kind == .large || candidate.kind == .medium, candidate.population >= 15_000 else { return false }
            guard candidate.code != base.code, candidate.code != home else { return false }
            return candidate.distanceKm(to: base) <= reach && !flown.contains { $0.serves(base.code, candidate.code) }
        }.sorted { $0.population != $1.population ? $0.population > $1.population : $0.code < $1.code }
        for partner in partners.prefix(12) where !isRemoteMarket(base.code, partner.code) {
            let km = base.distanceKm(to: partner)
            if Demand.passengersPerDay(from: base, to: partner, distanceKm: km) >= Tuning.rivalGrowthPaxPerDay {
                return RivalRoute(a: base.code, b: partner.code, frequency: 1, fareLevel: 1.0, startedDay: clock.dayIndex)
            }
        }
        return nil
    }
}
