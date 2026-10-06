// CoreWorld/Flights.swift: what happens when an aircraft departs and when it lands: boarding, money, wear.
import CoreCatalog
import CoreSim

extension World {
    // MARK: Market share and the waiting buckets

    /// The share of a leg's market this airline can win, from competition, price, reputation and frequency.
    func capture(route: Route, leg: LegState, from a: Airport, to b: Airport) -> Double {
        let smaller = Double(min(a.population, b.population))
        let intensity = min(1.0, (smaller / Tuning.competitiveCatchment).squareRoot())
        let perDay = leg.departuresLastWeek > 0 ? Double(leg.departuresLastWeek) / 7.0 : Double(leg.departuresThisWeek) / 3.0
        let ownShare = min(0.5, max(0.05, 0.05 + 0.004 * airline.reputation + 0.03 * perDay))
        let competitive = (1.0 - intensity) + intensity * ownShare
        let fareEffect = min(1.5, Powers.oneAndAHalf(1.0 / route.fareMultiplier))
        let quality = 0.85 + 0.0015 * airline.reputation
        return competitive * fareEffect * quality
    }

    /// Brings a leg's waiting buckets up to date: new people arrive, those who waited a while give up.
    mutating func refill(route r: Int, leg l: Int) {
        let route = routes[r]
        var leg = route.legs[l]
        let elapsedDays = Double(clock.minute - leg.lastUpdate) / Double(GameClock.minutesPerDay)
        guard elapsedDays > 0, let a = AirportCatalog.airport(leg.from), let b = AirportCatalog.airport(leg.to) else { return }
        let share = capture(route: route, leg: leg, from: a, to: b) * Seasons.factor(month: clock.date.month) * leg.maturity
        let paxPerDay = leg.marketPaxPerDay * share
        let cargoPerDay = leg.marketCargoKgPerDay * share
        let patience = 1.0 / (1.0 + Tuning.waitingDecayPerDay * elapsedDays)
        leg.waitingPax = min(2.0 * paxPerDay + 4.0, leg.waitingPax * patience + paxPerDay * elapsedDays)
        leg.waitingCargoKg = min(2.0 * cargoPerDay + 40.0, leg.waitingCargoKg * patience + cargoPerDay * elapsedDays)
        leg.lastUpdate = clock.minute
        routes[r].legs[l] = leg
    }

    // MARK: Departing

    func closureEnd(of airport: String) -> Int? {
        market.closures.first { $0.airport == airport && $0.untilMinute > clock.minute }?.untilMinute
    }

    /// Handles an aircraft whose turnaround ended: checks, then boards and takes off (or holds, repositions or breaks down).
    mutating func depart(_ i: Int) {
        guard let rid = aircraft[i].routeID, let r = routeIndex(rid), let type = aircraft[i].type else {
            aircraft[i].status = .idle
            return
        }
        let route = routes[r]
        guard let l = route.firstLeg(from: aircraft[i].location) else {
            if !startFerry(index: i, to: route.stops[0]) { aircraft[i].status = .idle; aircraft[i].routeID = nil }
            return
        }
        let leg = route.legs[l]
        guard let a = AirportCatalog.airport(leg.from), let b = AirportCatalog.airport(leg.to) else { aircraft[i].status = .idle; return }

        // Weather: wait at the gate until the airport reopens.
        if let until = closureEnd(of: leg.from) ?? closureEnd(of: leg.to) {
            aircraft[i].status = .boarding(until: until)
            return
        }

        // Scheduled check when worn.
        if aircraft[i].condition < Tuning.maintenanceThreshold {
            let days = max(1, Int((Tuning.conditionAfterCheck - aircraft[i].condition) / 10.0))
            aircraft[i].status = .maintenance(until: clock.minute + days * GameClock.minutesPerDay)
            return
        }

        // Schedule: wait for the next departure slot on this leg.
        if clock.minute < leg.nextSlot {
            aircraft[i].status = .boarding(until: leg.nextSlot)
            return
        }

        // Crew day: no more flying today, resume early tomorrow.
        let blockMinutes = max(1, Int((type.blockHours(km: leg.distanceKm) * 60).rounded()))
        let dayLimit = Int(Tuning.maxBlockHoursPerDay(level: type.level) * 60)
        if aircraft[i].blockMinutesToday > 0 && aircraft[i].blockMinutesToday + blockMinutes > dayLimit {
            aircraft[i].status = .boarding(until: (clock.dayIndex + 1) * GameClock.minutesPerDay + 6 * 60)
            return
        }

        // Failure on the ground. The roll is always drawn so the random stream does not depend on condition.
        let wear = 1.0 + (100.0 - aircraft[i].condition) / 25.0
        if rng.unit() < Tuning.breakdownPerDeparture * wear {
            raiseBreakdown(aircraftIndex: i, type: type)
            return
        }

        // Board.
        refill(route: r, leg: l)
        var bucket = routes[r].legs[l]
        let passengers = min(type.seats, Int(bucket.waitingPax))
        let cargoLimit = Double(type.cargoKg) * Tuning.cargoLoadLimit
        let cargo = route.carriesCargo ? Int(min(cargoLimit, bucket.waitingCargoKg)) : 0
        bucket.waitingPax -= Double(passengers)
        bucket.waitingCargoKg -= Double(cargo)
        bucket.departuresThisWeek += 1
        bucket.nextSlot = clock.minute + route.headwayMinutes
        routes[r].legs[l] = bucket

        let fare = leg.marketFare * route.fareMultiplier
        let revenue = Double(passengers) * fare * (1.0 - Tuning.salesShare) + Double(cargo) * Fares.cargoRate(distanceKm: leg.distanceKm)
        let wearFactor = Valuation.wearFactor(ageYears: aircraft[i].ageYears(atDay: clock.dayIndex), condition: aircraft[i].condition)
        let costs = LegEconomics.cost(type: type, from: a, to: b, distanceKm: leg.distanceKm, fuelIndex: market.fuelIndex, wearFactor: wearFactor)
        let cost = costs.total + Double(passengers) * LegEconomics.perPassenger(from: a, to: b) + Double(cargo) * Tuning.cargoHandlingPerKg

        aircraft[i].flight = Flight(from: leg.from, to: leg.to, departedMinute: clock.minute, distanceKm: leg.distanceKm, passengers: passengers, cargoKg: cargo,
                                    revenue: Int(revenue.rounded()), cost: Int(cost.rounded()), isFerry: false)
        aircraft[i].legIndex = l
        aircraft[i].blockMinutesToday += blockMinutes
        aircraft[i].status = .flying(until: clock.minute + blockMinutes)
    }

    /// Flies the aircraft empty to an airport (to reach a route that starts elsewhere). False if it cannot get there.
    @discardableResult
    mutating func startFerry(index i: Int, to code: String) -> Bool {
        guard let type = aircraft[i].type, let from = AirportCatalog.airport(aircraft[i].location), let to = AirportCatalog.airport(code),
              type.canLand(at: to) else { return false }
        let km = from.distanceKm(to: to)
        guard type.canFly(km: km) else { return false }
        let costs = LegEconomics.cost(type: type, from: from, to: to, distanceKm: km, fuelIndex: market.fuelIndex)
        let minutes = max(1, Int((type.blockHours(km: km) * 60).rounded()))
        aircraft[i].flight = Flight(from: from.code, to: to.code, departedMinute: clock.minute, distanceKm: km, passengers: 0, cargoKg: 0, revenue: 0,
                                    cost: Int(costs.total.rounded()), isFerry: true)
        aircraft[i].status = .flying(until: clock.minute + minutes)
        return true
    }

    // MARK: Landing

    mutating func arrive(_ i: Int) {
        guard let flight = aircraft[i].flight else {
            aircraft[i].status = aircraft[i].routeID == nil ? .idle : .boarding(until: clock.minute)
            return
        }
        earn(flight.revenue)
        spendOnFlights(flight.cost)
        let minutes = clock.minute - flight.departedMinute
        aircraft[i].condition = max(0, aircraft[i].condition - Double(minutes) / 60.0 * Tuning.conditionLossPerBlockHour)
        aircraft[i].location = flight.to
        aircraft[i].flight = nil
        aircraft[i].totalFlights += 1
        aircraft[i].totalBlockMinutes += minutes

        if !flight.isFerry {
            airline.stats.passengers += flight.passengers
            airline.stats.cargoKg += flight.cargoKg
            airline.stats.flights += 1
            airline.reputation = min(100, airline.reputation + 0.0004 * (1.0 + Double(flight.passengers) / Double(max(1, aircraft[i].type?.seats ?? 1))))
            if let rid = aircraft[i].routeID, let r = routeIndex(rid), let l = routes[r].firstLeg(from: flight.from), routes[r].legs[l].to == flight.to {
                routes[r].flights += 1
                routes[r].revenueThisMonth += flight.revenue
                routes[r].costThisMonth += flight.cost
                routes[r].legs[l].passengersCarried += flight.passengers
                routes[r].legs[l].revenue += flight.revenue
                routes[r].legs[l].maturity = min(1.0, routes[r].legs[l].maturity + 0.006)
            }
        }

        if aircraft[i].routeID == nil {
            aircraft[i].status = .idle
        } else {
            let engine = aircraft[i].type?.engine ?? .turboprop
            let turnaround = max(10, Int((Tuning.turnaroundHours(engine) * 60).rounded()))
            aircraft[i].status = .boarding(until: clock.minute + turnaround)
        }
    }
}
