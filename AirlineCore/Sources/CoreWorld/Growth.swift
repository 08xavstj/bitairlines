// CoreWorld/Growth.swift: growing out of the bush. Selling a route to a local operator, leaving an airport for good.
// Moving the headquarters and trading in an aircraft are in GrowthMoves.swift; suggested routes to bigger cities in RouteIdeasBigger.swift.
// Codes and numbers only; the app writes the words.
import CoreCatalog

extension Tuning {
    /// A local operator pays this many days of a route's average daily profit (over the last week) to take it over.
    public static let routeSaleDays = 60
    /// Share of the build price paid back for the facilities at an airport the airline leaves.
    public static let leaveAirportRefundShare = 0.4
    /// The lowest certificate level that may move its headquarters.
    public static let headquartersMoveLevel = 2
    /// Fee to move the headquarters, per certificate level, at a small airport (bigger airports cost more, see `World.sizeFactor`).
    public static let headquartersFeePerLevel = 100_000
    /// Catchment population from which an airport counts as a bigger city for suggested routes, by certificate level 1...7.
    public static let biggerCityPopulation: [Int] = [10_000, 30_000, 100_000, 300_000, 1_000_000, 3_000_000, 6_000_000]
    /// A network airport with at least this share of the bigger-city population is a starting point for bigger-city routes.
    public static let biggerCityOriginShare = 0.25

    /// Catchment population from which an airport counts as a bigger city at this level.
    public static func biggerCityPopulation(level: Int) -> Int {
        biggerCityPopulation[min(max(level, 1), biggerCityPopulation.count) - 1]
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

    /// What a local operator pays for the route today: `Tuning.routeSaleDays` days of its average daily profit over the last week, 0 if it loses money.
    public func routeSalePrice(routeID: Int) -> Int {
        guard let r = routeIndex(routeID) else { return 0 }
        let book = routes[r].book
        let perDay = Double(book.recent.profit) / Double(max(1, book.recentDays))
        return max(0, Int((perDay * Double(Tuning.routeSaleDays)).rounded()))
    }

    /// Hands a route over to a local operator: it closes, its aircraft are free (a shared aircraft keeps its other routes), and the
    /// operator pays `routeSalePrice`. Returns the price.
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
        routes.removeAll { $0.id == routeID }
        refreshAutoFrequency(routeIDs: others)
        airline.cash += price
        addNews(.growth, subject: "sold:" + name, amount: price)
        return price
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
        return plan
    }
}
