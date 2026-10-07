// CoreWorld/RouteActions.swift: creating routes and putting aircraft on them. Once assigned, aircraft fly the route forever on their own.
import CoreCatalog
import CoreSim

extension World {
    public static let maxStops = 6

    /// Why a list of stops cannot become a route right now (nil if it can). Lets the app show the problem before the player commits.
    public func routeProblem(stops: [String]) -> WorldError? {
        guard stops.count >= 2 else { return .routeNeedsTwoStops }
        guard stops.count <= World.maxStops else { return .tooManyStops }
        guard Set(stops).count == stops.count else { return .duplicateStops }
        for code in stops {
            guard let airport = AirportCatalog.airport(code) else { return .unknownAirport(code) }
            let required = Progression.requiredLevel(for: airport)
            if code != airline.home && required > airline.level { return .airportLevelTooHigh(airport: code, required: required) }
        }
        for code in stops {
            if let airport = AirportCatalog.airport(code), !airline.permits.contains(airport.country) {
                return .permitRequired(country: airport.country, price: permitPrice(country: airport.country))
            }
        }
        return nil
    }

    /// The legs of a cycle through the stops, with the market numbers for each; nil if an airport is unknown.
    /// A leg the airline already flies on another route gets its share of the market, not a second market (see `shareMarkets`).
    func makeLegs(stops: [String]) -> [LegState]? {
        var legs: [LegState] = []
        for (i, code) in stops.enumerated() {
            guard let a = AirportCatalog.airport(code), let b = AirportCatalog.airport(stops[(i + 1) % stops.count]) else { return nil }
            let km = a.distanceKm(to: b)
            let sharing = Double(legsFlown(from: a.code, to: b.code) + 1)
            legs.append(LegState(from: a.code, to: b.code, distanceKm: km, marketPaxPerDay: Demand.passengersPerDay(from: a, to: b, distanceKm: km) / sharing,
                                 marketCargoKgPerDay: Demand.cargoKgPerDay(from: a, to: b) / sharing, marketFare: Fares.market(from: a, to: b, distanceKm: km),
                                 waitingPax: 0, waitingCargoKg: 0, lastUpdate: clock.minute, maturity: Tuning.minimumMaturity, passengersCarried: 0, revenue: 0,
                                 departuresThisWeek: 0, departuresLastWeek: 0, nextSlot: clock.minute))
        }
        return legs
    }

    /// Opens a route through the stops, flown as a cycle. Returns the route id.
    @discardableResult
    public mutating func createRoute(stops: [String], name: String? = nil) throws -> Int {
        if let problem = routeProblem(stops: stops) { throw problem }
        guard var legs = makeLegs(stops: stops) else { throw WorldError.unknownAirport(stops.first ?? "") }
        // The very first route starts fully known, so the first session pays (FirstSession.swift).
        if opensFirstRoute {
            for l in legs.indices { legs[l].maturity = Tuning.firstRouteMaturity }
        }
        let id = takeRouteID()
        routes.append(Route(id: id, name: name ?? stops.map { AirportCatalog.airport($0)?.label ?? $0 }.joined(separator: " - "), stops: stops, fareMultiplier: 1.0, carriesCargo: true, frequency: 2.0, autoFrequency: true, legs: legs, aircraftIDs: [],
                            openedDay: clock.dayIndex, flights: 0, revenueThisMonth: 0, costThisMonth: 0, revenueLastMonth: 0, costLastMonth: 0))
        shareMarkets(pairs: routePairs(routes[routes.count - 1]))
        addNews(.routeOpened, subject: routes[routes.count - 1].name, amount: id)
        refreshConnections()
        return id
    }

    // MARK: One market per pair

    /// The airport pairs a route flies, in the direction flown.
    func routePairs(_ route: Route) -> [(from: String, to: String)] { route.legs.map { (from: $0.from, to: $0.to) } }

    /// How many of the airline's legs fly from `from` to `to`.
    func legsFlown(from: String, to: String) -> Int {
        routes.reduce(0) { n, route in n + route.legs.filter { $0.from == from && $0.to == to }.count }
    }

    /// Splits each pair's market evenly between the airline's legs that fly it, so a second route on the same pair shares the
    /// people and freight instead of finding a market of its own. Called when a route opens or closes.
    mutating func shareMarkets(pairs: [(from: String, to: String)]) {
        for pair in pairs {
            let n = legsFlown(from: pair.from, to: pair.to)
            guard n > 0, let a = AirportCatalog.airport(pair.from), let b = AirportCatalog.airport(pair.to) else { continue }
            let pax = Demand.passengersPerDay(from: a, to: b, distanceKm: a.distanceKm(to: b)) / Double(n)
            let cargo = Demand.cargoKgPerDay(from: a, to: b) / Double(n)
            for r in routes.indices {
                for l in routes[r].legs.indices where routes[r].legs[l].from == pair.from && routes[r].legs[l].to == pair.to {
                    routes[r].legs[l].marketPaxPerDay = pax
                    routes[r].legs[l].marketCargoKgPerDay = cargo
                }
            }
        }
    }

    public mutating func deleteRoute(id: Int) throws {
        guard let r = routeIndex(id) else { throw WorldError.unknownRoute(id) }
        // A shared aircraft keeps its other routes (which now have more of it); one with no route left parks.
        var others: [Int] = []
        for planeID in routes[r].aircraftIDs {
            guard let i = aircraftIndex(planeID) else { continue }
            others += aircraft[i].allRouteIDs.filter { $0 != id }
            detach(i, fromRoute: id)
        }
        let pairs = routePairs(routes[r])
        routes.removeAll { $0.id == id }
        refreshAutoFrequency(routeIDs: others)
        shareMarkets(pairs: pairs)
        refreshConnections()
    }

    public mutating func setFare(routeID: Int, multiplier: Double) throws {
        guard let r = routeIndex(routeID) else { throw WorldError.unknownRoute(routeID) }
        routes[r].fareMultiplier = min(Route.maxFare, max(Route.minFare, multiplier))
    }

    public mutating func setFrequency(routeID: Int, perDay: Double) throws {
        guard let r = routeIndex(routeID) else { throw WorldError.unknownRoute(routeID) }
        routes[r].frequency = min(Route.maxFrequency, max(Route.minFrequency, perDay))
        routes[r].autoFrequency = false
    }

    /// A sensible number of departures per day for a route flown by `aircraftCount` aircraft of this type: enough to carry the market at a healthy load,
    /// never more than the aircraft can actually fly in a day.
    public func suggestedFrequency(route: Route, type: AircraftType, aircraftCount: Int = 1) -> Double {
        let target = min(demandFrequency(route: route, type: type), maxFrequency(route: route, type: type, aircraftCount: aircraftCount))
        return Route.snapFrequency(target)
    }

    /// Departures per day the market would fill at a healthy load with this type (the thinnest leg limits it). Only the airline's
    /// own part of a contested market counts, and that part grows with the schedule, so the schedule is worked out twice.
    public func demandFrequency(route: Route, type: AircraftType) -> Double {
        let seats = max(1.0, Double(type.seats) * 0.8)
        let whole = (route.legs.map { ($0.marketPaxPerDay + $0.connectingPaxPerDay) * 0.75 }.min() ?? 0) / seats
        var f = whole
        for _ in 0..<2 {
            let perDay = f
            f = (route.legs.map { ($0.marketPaxPerDay + $0.connectingPaxPerDay) * 0.75 * contestedShare(leg: $0, perDay: perDay) }.min() ?? 0) / seats
        }
        return f
    }

    /// The part of a leg's market the airline can win against other airlines when it flies `perDay` departures: all of a remote
    /// market, at most half of a big contested one. The competition part of `capture` (Flights.swift); keep the two the same.
    func contestedShare(leg: LegState, perDay: Double) -> Double {
        guard let a = AirportCatalog.airport(leg.from), let b = AirportCatalog.airport(leg.to) else { return 1.0 }
        let smaller = Double(min(a.population, b.population))
        var intensity = min(1.0, (smaller / Tuning.competitiveCatchment).squareRoot())
        let rivals = rivalRoutes(leg.from, leg.to)
        if !rivals.isEmpty { intensity = max(intensity, rivalPressure(rivals)) }
        let ownShare = min(0.5, max(0.05, 0.05 + 0.004 * airline.reputation + 0.03 * perDay))
        return (1.0 - intensity) + intensity * ownShare
    }

    /// Most departures per day `aircraftCount` aircraft of this type can fly on the route, within crew hours.
    public func maxFrequency(route: Route, type: AircraftType, aircraftCount: Int) -> Double {
        Double(max(1, aircraftCount)) * cyclesPerAircraftPerDay(route: route, type: type)
    }

    /// Whole trips round the route one aircraft can fly in a day: limited by the 24-hour day and by the crew's flying hours.
    public func cyclesPerAircraftPerDay(route: Route, type: AircraftType) -> Double {
        let block = route.legs.reduce(0.0) { $0 + type.blockHours(km: $1.distanceKm) }
        let cycle = block + turnaroundHours(type.engine) * Double(route.legs.count)
        return min(24.0 / max(0.5, cycle), Tuning.maxBlockHoursPerDay(level: type.level) * 0.9 / max(0.25, block))
    }

    /// Re-picks the schedule from the aircraft now on the route (and turns automatic scheduling back on).
    public mutating func applySuggestedFrequency(routeID: Int) throws {
        guard let r = routeIndex(routeID) else { throw WorldError.unknownRoute(routeID) }
        let planes = routes[r].aircraftIDs.compactMap { id in aircraft.first { $0.id == id } }
        guard let type = planes.first?.type else { return }
        let share = aircraftShare(onRoute: routeID)
        routes[r].frequency = suggestedFrequency(route: routes[r], type: type, aircraftShare: share)
        routes[r].autoFrequency = true
    }

    public mutating func setCargo(routeID: Int, enabled: Bool) throws {
        guard let r = routeIndex(routeID) else { throw WorldError.unknownRoute(routeID) }
        routes[r].carriesCargo = enabled
    }

    public mutating func rename(routeID: Int, to name: String) throws {
        guard let r = routeIndex(routeID) else { throw WorldError.unknownRoute(routeID) }
        routes[r].name = name
    }

    /// Why this aircraft type (with these kits) cannot fly the route (nil if it can). Seasons are not counted: a lake that freezes
    /// in winter still fits a floatplane.
    public func fitProblem(type: AircraftType, route: Route, kits: [Kit] = []) -> WorldError? {
        let cap = Capability(type: type, kits: kits)
        for code in route.stops {
            guard let airport = AirportCatalog.airport(code) else { return .unknownAirport(code) }
            if !canUse(cap, at: airport) { return .aircraftCannotUse(airport: code) }
        }
        for leg in route.legs where !type.canFly(km: leg.distanceKm) { return .outOfRange(km: Int(leg.distanceKm)) }
        if ops.mode.fuelOnlyWhereSold, let dry = fuelProblem(type: type, route: route) { return dry }
        return nil
    }

    /// Realism: every stretch between fuel stops must be within the aircraft's range. Nil if it is.
    func fuelProblem(type: AircraftType, route: Route) -> WorldError? {
        let n = route.legs.count
        let sells = route.stops.map { code in AirportCatalog.airport(code).map { sellsFuel($0) } ?? false }
        guard n > 0, let start = sells.firstIndex(of: true) else { return .noFuel(airport: route.stops.first ?? "") }
        var since = 0.0
        for k in 0..<n {
            let l = (start + k) % n
            since += route.legs[l].distanceKm
            if since > Double(type.rangeKm) { return .noFuel(airport: route.legs[l].from) }
            if sells[(l + 1) % n] { since = 0 }
        }
        return nil
    }

    /// Puts an aircraft on a route, and on this route only (it stops flying any other). If it is parked somewhere else it first flies there empty.
    public mutating func assign(aircraftID: Int, toRoute routeID: Int) throws {
        // The same checks the app shows before the player taps (PlaneChoices.swift), including whether it can get there empty.
        if let problem = assignProblem(aircraftID: aircraftID, routeID: routeID) { throw problem }
        guard let i = aircraftIndex(aircraftID), let r = routeIndex(routeID), let type = aircraft[i].type else { throw WorldError.unknownAircraft(aircraftID) }

        let before = aircraft[i].allRouteIDs
        detachFromAllRoutes(i)
        aircraft[i].routeID = routeID
        routes[r].aircraftIDs.append(aircraftID)
        if routes[r].autoFrequency {
            let share = aircraftShare(onRoute: routeID)
            routes[r].frequency = suggestedFrequency(route: routes[r], type: type, aircraftShare: share)
        }
        // The routes it flew before now have less of it (or none).
        refreshAutoFrequency(routeIDs: before.filter { $0 != routeID })
        // An aircraft held at the gate for its old route (weather, crew hours, a frozen lake) looks again at once.
        if case .boarding = aircraft[i].status { aircraft[i].status = .boarding(until: clock.minute) }
        if case .idle = aircraft[i].status {
            if let leg = routes[r].firstLeg(from: aircraft[i].location) {
                aircraft[i].legIndex = leg
                aircraft[i].status = .boarding(until: clock.minute)
            } else if !startFerry(index: i, toAny: routes[r].stops) {
                // Not expected (assignProblem checked the way there), but never leave it on a route it cannot reach.
                aircraft[i].routeID = nil
                routes[r].aircraftIDs.removeAll { $0 == aircraftID }
                throw WorldError.outOfRange(km: 0)
            }
        }
    }

    /// Takes an aircraft off all its routes. If it is in the air it finishes the flight and then parks.
    /// Routes left on automatic scheduling pick a schedule for the aircraft they still have.
    public mutating func unassign(aircraftID: Int) throws {
        guard let i = aircraftIndex(aircraftID) else { throw WorldError.unknownAircraft(aircraftID) }
        let before = aircraft[i].allRouteIDs
        detachFromAllRoutes(i)
        if case .boarding = aircraft[i].status { aircraft[i].status = .idle }
        refreshAutoFrequency(routeIDs: before)
    }
}
