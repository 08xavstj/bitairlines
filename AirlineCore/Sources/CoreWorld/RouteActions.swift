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
                return .permitRequired(country: airport.country, price: Progression.permitPrice(country: airport.country))
            }
        }
        return nil
    }

    /// Opens a route through the stops, flown as a cycle. Returns the route id.
    @discardableResult
    public mutating func createRoute(stops: [String], name: String? = nil) throws -> Int {
        if let problem = routeProblem(stops: stops) { throw problem }
        var legs: [LegState] = []
        for (i, code) in stops.enumerated() {
            guard let a = AirportCatalog.airport(code), let b = AirportCatalog.airport(stops[(i + 1) % stops.count]) else { throw WorldError.unknownAirport(code) }
            let km = a.distanceKm(to: b)
            legs.append(LegState(from: a.code, to: b.code, distanceKm: km, marketPaxPerDay: Demand.passengersPerDay(from: a, to: b, distanceKm: km),
                                 marketCargoKgPerDay: Demand.cargoKgPerDay(from: a, to: b), marketFare: Fares.market(from: a, to: b, distanceKm: km),
                                 waitingPax: 0, waitingCargoKg: 0, lastUpdate: clock.minute, maturity: Tuning.minimumMaturity, passengersCarried: 0, revenue: 0,
                                 departuresThisWeek: 0, departuresLastWeek: 0, nextSlot: clock.minute))
        }
        let id = takeRouteID()
        routes.append(Route(id: id, name: name ?? stops.joined(separator: "-"), stops: stops, fareMultiplier: 1.0, carriesCargo: true, frequency: 2.0, autoFrequency: true, legs: legs, aircraftIDs: [],
                            openedDay: clock.dayIndex, flights: 0, revenueThisMonth: 0, costThisMonth: 0, revenueLastMonth: 0, costLastMonth: 0))
        addNews(.routeOpened, subject: routes[routes.count - 1].name, amount: id)
        return id
    }

    public mutating func deleteRoute(id: Int) throws {
        guard let r = routeIndex(id) else { throw WorldError.unknownRoute(id) }
        for planeID in routes[r].aircraftIDs { try? unassign(aircraftID: planeID) }
        routes.removeAll { $0.id == id }
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
        let demand = (route.legs.map { $0.marketPaxPerDay * 0.75 }.min() ?? 0)
        let wanted = demand / max(1.0, Double(type.seats) * 0.8)
        let cycleHours = route.legs.reduce(0.0) { $0 + type.blockHours(km: $1.distanceKm) + Tuning.turnaroundHours(type.engine) }
        let capacity = Tuning.maxBlockHoursPerDay(level: type.level) * 0.9 / max(0.5, cycleHours) * Double(max(1, aircraftCount))
        let target = min(wanted, capacity)
        return Route.frequencySteps.min { abs($0 - target) < abs($1 - target) } ?? 1
    }

    /// Re-picks the schedule from the aircraft now on the route (and turns automatic scheduling back on).
    public mutating func applySuggestedFrequency(routeID: Int) throws {
        guard let r = routeIndex(routeID) else { throw WorldError.unknownRoute(routeID) }
        let planes = routes[r].aircraftIDs.compactMap { id in aircraft.first { $0.id == id } }
        guard let type = planes.first?.type else { return }
        routes[r].frequency = suggestedFrequency(route: routes[r], type: type, aircraftCount: planes.count)
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

    /// Why this aircraft type cannot fly the route (nil if it can).
    public func fitProblem(type: AircraftType, route: Route) -> WorldError? {
        for code in route.stops {
            guard let airport = AirportCatalog.airport(code) else { return .unknownAirport(code) }
            if !type.canLand(at: airport) { return .aircraftCannotUse(airport: code) }
        }
        for leg in route.legs where !type.canFly(km: leg.distanceKm) { return .outOfRange(km: Int(leg.distanceKm)) }
        return nil
    }

    /// Puts an aircraft on a route. If it is parked somewhere else it first flies there empty.
    public mutating func assign(aircraftID: Int, toRoute routeID: Int) throws {
        guard let i = aircraftIndex(aircraftID) else { throw WorldError.unknownAircraft(aircraftID) }
        guard let r = routeIndex(routeID) else { throw WorldError.unknownRoute(routeID) }
        guard aircraft[i].isDelivered else { throw WorldError.notDelivered }
        if case .grounded = aircraft[i].status { throw WorldError.aircraftBusy }
        guard let type = aircraft[i].type else { throw WorldError.unknownType(aircraft[i].typeID) }
        if let problem = fitProblem(type: type, route: routes[r]) { throw problem }

        if let old = aircraft[i].routeID, let oldIndex = routeIndex(old) { routes[oldIndex].aircraftIDs.removeAll { $0 == aircraftID } }
        aircraft[i].routeID = routeID
        routes[r].aircraftIDs.append(aircraftID)
        if routes[r].autoFrequency { routes[r].frequency = suggestedFrequency(route: routes[r], type: type, aircraftCount: routes[r].aircraftIDs.count) }
        if case .idle = aircraft[i].status {
            if let leg = routes[r].firstLeg(from: aircraft[i].location) {
                aircraft[i].legIndex = leg
                aircraft[i].status = .boarding(until: clock.minute)
            } else if !startFerry(index: i, to: routes[r].stops[0]) {
                aircraft[i].routeID = nil
                routes[r].aircraftIDs.removeAll { $0 == aircraftID }
                throw WorldError.outOfRange(km: 0)
            }
        }
    }

    /// Takes an aircraft off its route. If it is in the air it finishes the flight and then parks.
    public mutating func unassign(aircraftID: Int) throws {
        guard let i = aircraftIndex(aircraftID) else { throw WorldError.unknownAircraft(aircraftID) }
        if let rid = aircraft[i].routeID, let r = routeIndex(rid) { routes[r].aircraftIDs.removeAll { $0 == aircraftID } }
        aircraft[i].routeID = nil
        if case .boarding = aircraft[i].status { aircraft[i].status = .idle }
    }
}
