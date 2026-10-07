// CoreWorld/Growth.swift: growing out of the bush. Selling a route to a local operator, leaving an airport for good.
// Moving the headquarters and trading in an aircraft are in GrowthMoves.swift; suggested routes to bigger cities in RouteIdeasBigger.swift.
// Codes and numbers only; the app writes the words.
import CoreCatalog

extension Tuning {
    /// A local operator pays this many days of a route's proven daily profit (its average since it opened) to take it over...
    public static let routeSaleDays = 60
    /// ...nothing for a route flown fewer days than this...
    public static let routeSaleMinimumDays = 28
    /// ...and the full price only for a route flown this long; a younger one fetches its share of a year, so selling a route and
    /// opening it again does not pay.
    public static let routeSaleFullPriceDays = 365
    /// Share of the build price paid back for the facilities at an airport the airline leaves.
    public static let leaveAirportRefundShare = 0.4
    /// The lowest certificate level that may move its headquarters.
    public static let headquartersMoveLevel = 2
    /// Fee to move the headquarters, per certificate level, at a small airport (bigger airports cost more, see `World.sizeFactor`).
    public static let headquartersFeePerLevel = 100_000
    /// Catchment population from which an airport counts as a bigger city for suggested routes, by certificate level 1...7.
    public static let biggerCityPopulationByLevel: [Int] = [10_000, 30_000, 100_000, 300_000, 1_000_000, 3_000_000, 6_000_000]
    /// A network airport with at least this share of the bigger-city population is a starting point for bigger-city routes.
    public static let biggerCityOriginShare = 0.25

    /// Catchment population from which an airport counts as a bigger city at this level.
    public static func biggerCityPopulation(level: Int) -> Int {
        biggerCityPopulationByLevel[min(max(level, 1), biggerCityPopulationByLevel.count) - 1]
    }
}

/// What leaving an airport would do: the routes sold, the facilities sold, the slots sold back, the aircraft sent home and the jobs dropped.
public struct LeaveAirportPlan: Sendable, Hashable {
    public var airport: String
    public var routeIDs: [Int]
    /// What local operators pay for those routes together.
    public var routeSale: Int
    public var facilities: [Facility]
    /// What the facilities fetch (a share of their build price).
    public var facilityRefund: Int
    public var slots: Int
    public var slotRefund: Int
    /// Jobs on the board to or from the airport that nobody has taken.
    public var jobs: Int

    public var total: Int { routeSale + facilityRefund + slotRefund }
}

extension World {
    // MARK: Selling a route

    /// Days the route has been open.
    public func routeAgeDays(routeID: Int) -> Int {
        guard let r = routeIndex(routeID) else { return 0 }
        return max(0, clock.dayIndex - routes[r].openedDay)
    }

    /// What a local operator pays for the route today: `Tuning.routeSaleDays` days of its proven profit (the average per day since
    /// it opened, aircraft costs included), scaled down for a route younger than `Tuning.routeSaleFullPriceDays`. 0 for a route
    /// younger than `Tuning.routeSaleMinimumDays` or one that loses money.
    public func routeSalePrice(routeID: Int) -> Int {
        guard let r = routeIndex(routeID) else { return 0 }
        let days = routeAgeDays(routeID: routeID)
        guard days >= Tuning.routeSaleMinimumDays else { return 0 }
        let perDay = Double(routes[r].sinceOpened.profit) / Double(days)
        let established = min(1.0, Double(days) / Double(Tuning.routeSaleFullPriceDays))
        return max(0, Int((perDay * Double(Tuning.routeSaleDays) * established).rounded()))
    }

    /// Hands a route over to a local operator: it closes, its aircraft are free (a shared aircraft keeps its other routes), and the
    /// operator pays `routeSalePrice`. The operator keeps flying the route's airports (see `handOver`). Returns the price.
    @discardableResult
    public mutating func sellRoute(routeID: Int) throws -> Int {
        guard let r = routeIndex(routeID) else { throw WorldError.unknownRoute(routeID) }
        let price = routeSalePrice(routeID: routeID)
        let name = routes[r].name
        var others: [Int] = []
        for planeID in routes[r].aircraftIDs {
            guard let i = aircraftIndex(planeID) else { continue }
            others += aircraft[i].allRouteIDs.filter { $0 != routeID }
            detach(i, fromRoute: routeID)
        }
        let sold = routes[r]
        routes.removeAll { $0.id == routeID }
        refreshAutoFrequency(routeIDs: others)
        shareMarkets(pairs: routePairs(sold))
        handOver(sold)
        airline.cash += price
        addNews(.growth, subject: "sold:" + name, amount: price)
        refreshConnections()
        settleOverdraft()
        return price
    }

    /// The operator who bought a route keeps flying it: each of its airport pairs that no rival flies yet goes to the rival airline
    /// based nearest the route, at the route's schedule and the going fare. Opening the same pair again means sharing it with them,
    /// until they are beaten on it for a while (RivalMoves.swift).
    mutating func handOver(_ route: Route) {
        let rivals = ops.rivals
        guard !rivals.isEmpty, let first = route.stops.first, let start = AirportCatalog.airport(first) else { return }
        var nearest = 0
        var nearestKm = Double.greatestFiniteMagnitude
        for (v, rival) in rivals.enumerated() {
            guard let home = AirportCatalog.airport(rival.home) else { continue }
            let km = home.distanceKm(to: start)
            if km < nearestKm {
                nearest = v
                nearestKm = km
            }
        }
        var added: [RivalRoute] = []
        for leg in route.legs {
            let taken = !rivalRoutes(leg.from, leg.to).isEmpty || added.contains { $0.serves(leg.from, leg.to) }
            if taken { continue }
            added.append(RivalRoute(a: leg.from, b: leg.to, frequency: route.frequency, fareLevel: 1.0, startedDay: clock.dayIndex))
        }
        guard !added.isEmpty else { return }
        ops.rivals[nearest].routes.append(contentsOf: added)
    }

    // MARK: Leaving an airport

    /// Why the airline cannot leave this airport (nil if it can): not the headquarters, and only an airport it uses.
    public func leaveAirportProblem(code: String) -> WorldError? {
        guard AirportCatalog.airport(code) != nil else { return .unknownAirport(code) }
        if code == airline.home { return .isHeadquarters }
        let used = routes.contains { $0.stops.contains(code) } || base(at: code) != nil || slotsHeld(at: code) > 0
        return used ? nil : .invalidChoice
    }

    /// What leaving the airport would do, for the confirm dialog.
    public func leaveAirportPlan(code: String) -> LeaveAirportPlan {
        let routeIDs = routes.filter { $0.stops.contains(code) }.map(\.id)
        let facilities = base(at: code)?.facilities ?? []
        var refund = 0
        var slotRefund = 0
        let slots = slotsHeld(at: code)
        if let airport = AirportCatalog.airport(code) {
            for f in facilities { refund += Int((Double(facilityPrice(f, at: airport)) * Tuning.leaveAirportRefundShare).rounded()) }
            slotRefund = slotPrice(at: airport) * slots / 2
        }
        let jobs = ops.jobs.filter { !$0.isTaken && ($0.from == code || $0.to == code) }.count
        return LeaveAirportPlan(airport: code, routeIDs: routeIDs, routeSale: routeIDs.reduce(0) { $0 + routeSalePrice(routeID: $1) },
                                facilities: facilities, facilityRefund: refund, slots: slots, slotRefund: slotRefund, jobs: jobs)
    }

    /// Leaves an airport for good: sells every route through it, sells its facilities (a share of the build price) and slots, sends
    /// aircraft parked there home (those that cannot make it stay parked) and drops the jobs to or from it nobody has taken.
    @discardableResult
    public mutating func leaveAirport(code: String) throws -> LeaveAirportPlan {
        if let problem = leaveAirportProblem(code: code) { throw problem }
        let plan = leaveAirportPlan(code: code)
        for rid in plan.routeIDs { try sellRoute(routeID: rid) }
        if !plan.facilities.isEmpty {
            ops.bases.removeAll { $0.airport == code }
            airline.cash += plan.facilityRefund
        }
        if plan.slots > 0 { try sellSlots(at: code, count: plan.slots) }
        var jobs = ops.jobs
        jobs.removeAll { !$0.isTaken && ($0.from == code || $0.to == code) }
        ops.jobs = jobs
        let home = airline.home
        for i in aircraft.indices where aircraft[i].location == code && aircraft[i].routeID == nil && aircraft[i].jobID == nil && !aircraft[i].awaitingRestoration {
            if case .idle = aircraft[i].status { _ = startFerry(index: i, to: home) }
        }
        refreshJobArea()
        addNews(.growth, subject: "left:" + code, amount: plan.total)
        settleOverdraft()
        return plan
    }
}
