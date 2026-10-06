// CoreWorld/Flights.swift: what happens when an aircraft departs and when it lands: boarding, money, wear.
import CoreCatalog
import CoreSim

extension World {
    // MARK: Market share and the waiting buckets

    /// The share of a leg's market this airline can win, from competition, price, reputation, frequency and service.
    func capture(route: Route, leg: LegState, from a: Airport, to b: Airport) -> Double {
        let smaller = Double(min(a.population, b.population))
        var intensity = min(1.0, (smaller / Tuning.competitiveCatchment).squareRoot())
        let rivals = rivalRoutes(leg.from, leg.to)
        if !rivals.isEmpty { intensity = max(intensity, Tuning.rivalIntensity) }
        let perDay = leg.departuresLastWeek > 0 ? Double(leg.departuresLastWeek) / 7.0 : Double(leg.departuresThisWeek) / 3.0
        let ownShare = min(0.5, max(0.05, 0.05 + 0.004 * airline.reputation + 0.03 * perDay))
        let competitive = (1.0 - intensity) + intensity * ownShare
        // Fares are compared with the going fare, or with a rival's fare where one flies the same pair.
        let reference = rivals.map(\.fareLevel).min() ?? 1.0
        let fareEffect = min(1.5, Powers.oneAndAHalf(reference / route.fareMultiplier))
        let quality = 0.9 + 0.001 * airline.reputation
        return competitive * fareEffect * quality * route.service.captureFactor * captureFactor
    }

    /// Brings a leg's waiting buckets up to date: new people arrive, those who waited a while give up.
    mutating func refill(route r: Int, leg l: Int) {
        let route = routes[r]
        var leg = route.legs[l]
        let elapsedDays = Double(clock.minute - leg.lastUpdate) / Double(GameClock.minutesPerDay)
        guard elapsedDays > 0, let a = AirportCatalog.airport(leg.from), let b = AirportCatalog.airport(leg.to) else { return }
        let share = capture(route: route, leg: leg, from: a, to: b) * Seasons.factor(month: clock.date.month) * leg.maturity
        let boost = eventFactors(from: a, to: b)
        let paxPerDay = (leg.marketPaxPerDay + leg.connectingPaxPerDay) * share * boost.passengers
        let cargoPerDay = leg.marketCargoKgPerDay * share * boost.cargo
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

    /// The first minute of the month after `month` ends... used to park a floatplane until the lakes thaw (checked again then).
    func firstOfNextMonth() -> Int {
        let date = clock.date
        var day = clock.dayIndex
        while CalendarDate(dayIndex: day).month == date.month { day += 1 }
        return day * GameClock.minutesPerDay + 8 * 60
    }

    /// Handles an aircraft whose turnaround ended: checks, then boards and takes off (or holds, repositions or breaks down).
    mutating func depart(_ i: Int) {
        if let jobID = aircraft[i].jobID {
            departOnJob(i, jobID: jobID)
            return
        }
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

        // Frozen lake: a floatplane waits for the thaw.
        let cap = Capability(type: type, kits: aircraft[i].kits)
        let month = clock.date.month
        if !canUse(cap, at: a, month: month) || !canUse(cap, at: b, month: month) {
            aircraft[i].status = .boarding(until: firstOfNextMonth())
            return
        }

        // Scheduled check when worn (quicker at a base with a hangar).
        if aircraft[i].condition < Tuning.maintenanceThreshold {
            var days = max(1, Int((Tuning.conditionAfterCheck - aircraft[i].condition) / 10.0))
            if hasHangar(at: aircraft[i].location) || has(.mechanicsGuild) { days = max(1, days / 2) }
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
        let tomorrowMorning = (clock.dayIndex + 1) * GameClock.minutesPerDay + 6 * 60
        if aircraft[i].blockMinutesToday > 0 && aircraft[i].blockMinutesToday + blockMinutes > dayLimit {
            aircraft[i].status = .boarding(until: tomorrowMorning)
            return
        }

        // Daylight at unlit strips, and the day's slots at busy airports.
        if let wait = darkHold(from: a, to: b, blockMinutes: blockMinutes) {
            aircraft[i].status = .boarding(until: wait)
            return
        }
        if outOfSlots(at: a) {
            aircraft[i].status = .boarding(until: tomorrowMorning)
            return
        }

        // Pilots: someone rated and fit to fly.
        if !crewReady(i) {
            aircraft[i].status = .boarding(until: crewBackMinute(i) ?? clock.minute + GameClock.minutesPerDay)
            addNews(.noCrew, subject: aircraft[i].registration, amount: aircraft[i].id)
            return
        }

        // Failure on the ground. The roll is always drawn so the random stream does not depend on condition.
        let wear = 1.0 + (100.0 - aircraft[i].condition) / 25.0
        if rng.unit() < Tuning.breakdownPerDeparture * wear {
            raiseBreakdown(aircraftIndex: i, type: type)
            return
        }

        // Board.
        recordDeparture(scheduled: leg.nextSlot)
        useSlot(at: a)
        refill(route: r, leg: l)
        var bucket = routes[r].legs[l]
        let passengers = min(aircraft[i].seats, Int(bucket.waitingPax))
        let cargoLimit = Double(aircraft[i].cargoKg) * Tuning.cargoLoadLimit
        let cargo = route.carriesCargo ? Int(min(cargoLimit, bucket.waitingCargoKg)) : 0
        bucket.waitingPax -= Double(passengers)
        bucket.waitingCargoKg -= Double(cargo)
        bucket.departuresThisWeek += 1
        bucket.nextSlot = clock.minute + route.headwayMinutes
        routes[r].legs[l] = bucket

        let fare = leg.blendedFare * route.fareMultiplier
        let revenue = Double(passengers) * fare * (1.0 - Tuning.salesShare) + Double(cargo) * Fares.cargoRate(distanceKm: leg.distanceKm) * cargoRateFactor
        let flightCost = legCost(type: type, aircraftIndex: i, from: a, to: b, km: leg.distanceKm)
        let cost = flightCost + Double(passengers) * passengerCost(from: a, to: b, service: route.service) + Double(cargo) * Tuning.cargoHandlingPerKg

        aircraft[i].flight = Flight(from: leg.from, to: leg.to, departedMinute: clock.minute, distanceKm: leg.distanceKm, passengers: passengers, cargoKg: cargo,
                                    revenue: Int(revenue.rounded()), cost: Int(cost.rounded()), isFerry: false)
        aircraft[i].legIndex = l
        aircraft[i].blockMinutesToday += blockMinutes
        aircraft[i].status = .flying(until: clock.minute + blockMinutes)
    }

    /// Flies the aircraft empty to an airport (to reach a route or a job that starts elsewhere). False if it cannot get there.
    @discardableResult
    mutating func startFerry(index i: Int, to code: String) -> Bool {
        guard let type = aircraft[i].type, let from = AirportCatalog.airport(aircraft[i].location), let to = AirportCatalog.airport(code),
              canUse(type: type, kits: aircraft[i].kits, at: to) else { return false }
        let km = from.distanceKm(to: to)
        guard type.canFly(km: km) else { return false }
        let cost = legCost(type: type, aircraftIndex: i, from: from, to: to, km: km)
        let minutes = max(1, Int((type.blockHours(km: km) * 60).rounded()))
        aircraft[i].flight = Flight(from: from.code, to: to.code, departedMinute: clock.minute, distanceKm: km, passengers: 0, cargoKg: 0, revenue: 0,
                                    cost: Int(cost.rounded()), isFerry: true)
        aircraft[i].status = .flying(until: clock.minute + minutes)
        return true
    }

    // MARK: Landing

    mutating func arrive(_ i: Int) {
        guard let flight = aircraft[i].flight else {
            aircraft[i].status = aircraft[i].routeID == nil && aircraft[i].jobID == nil ? .idle : .boarding(until: clock.minute)
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
        logHours(i, minutes: minutes)
        countScenarioFreight(kg: flight.cargoKg, at: flight.to)

        // A job that ends here is paid now, and the aircraft goes back to its route by itself.
        if landOnJob(i, flight: flight) { return }

        if !flight.isFerry {
            airline.stats.passengers += flight.passengers
            airline.stats.cargoKg += flight.cargoKg
            airline.stats.flights += 1
            var service = ServiceLevel.standard
            if let rid = aircraft[i].routeID, let r = routeIndex(rid), let l = routes[r].firstLeg(from: flight.from), routes[r].legs[l].to == flight.to {
                service = routes[r].service
                routes[r].flights += 1
                routes[r].revenueThisMonth += flight.revenue
                routes[r].costThisMonth += flight.cost
                routes[r].legs[l].passengersCarried += flight.passengers
                routes[r].legs[l].revenue += flight.revenue
                routes[r].legs[l].maturity = min(1.0, routes[r].legs[l].maturity + Tuning.maturityPerFlight)
            }
            airline.reputation = min(100, airline.reputation + reputationGain(passengers: flight.passengers, seats: aircraft[i].seats, service: service))
        }

        if aircraft[i].routeID == nil && aircraft[i].jobID == nil {
            aircraft[i].status = .idle
        } else {
            let engine = aircraft[i].type?.engine ?? .turboprop
            let turnaround = max(10, Int((turnaroundHours(engine) * 60).rounded()))
            aircraft[i].status = .boarding(until: clock.minute + turnaround)
        }
    }
}
