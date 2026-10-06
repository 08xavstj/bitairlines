// CoreWorld/DailyUpdate.swift: what happens at midnight: fixed costs, weekly and monthly chores, weather, money and certificate checks.
import CoreCatalog
import CoreSim

extension World {
    mutating func runDailyUpdate() {
        let day = clock.dayIndex
        books.append(today)
        if books.count > World.bookLimit { books.removeFirst(books.count - World.bookLimit) }
        today = DayBook(day: day, revenue: 0, flightCosts: 0, overhead: 0)

        var fixed = Tuning.headOfficePerDay(level: airline.level)
        for plane in aircraft where plane.isDelivered {
            if let type = plane.type { fixed += LegEconomics.fixedPerDay(type: type) }
        }
        spendOnOverhead(Int(fixed.rounded()))
        rollRouteBooks()

        for i in aircraft.indices { aircraft[i].blockMinutesToday = 0 }

        if clock.weekday == 0 { weeklyUpdate() }
        if clock.date.day == 1 { monthlyUpdate() }
        updateClosures()
        dailyOperations()
        checkMoney()
        checkCertificate()
    }

    /// Starts a new day in every route's book and charges each route the daily cost of the aircraft assigned to it: its fixed cost
    /// (the same amount just paid above), its pilots' salaries and its heavy checks spread over the days, the same costs the
    /// forecast counts. Head office stays with the airline.
    mutating func rollRouteBooks() {
        for r in routes.indices { routes[r].book.closeDay() }
        for plane in aircraft where plane.isDelivered {
            guard plane.routeID != nil else { continue }
            // A shared aircraft's day is split between the routes it flies.
            let share = aircraftDayCost(plane) * plane.routeShare
            for rid in plane.allRouteIDs {
                if let r = routeIndex(rid) { routes[r].book.add(RouteDay(aircraftCost: Int(share.rounded()))) }
            }
        }
    }

    /// What one aircraft costs a route for a day besides its flights: the fixed cost, the salaries of its own pilots, and its
    /// heavy checks spread over the days (at the hours it flew today). Read before `blockMinutesToday` is cleared at midnight.
    func aircraftDayCost(_ plane: Aircraft) -> Double {
        guard let type = plane.type else { return 0 }
        let salaries = ops.pilots.filter { $0.aircraftID == plane.id }.reduce(0) { $0 + $1.salaryPerMonth }
        let checks = heavyCheckPerDay(checkCost: Double(heavyCheckCost(plane)), blockHoursPerDay: Double(plane.blockMinutesToday) / 60.0)
        return LegEconomics.fixedPerDay(type: type) + Double(salaries) * 12.0 / 365.0 + checks
    }

    mutating func weeklyUpdate() {
        rotateListings()
        for r in routes.indices {
            for l in routes[r].legs.indices {
                routes[r].legs[l].departuresLastWeek = routes[r].legs[l].departuresThisWeek
                routes[r].legs[l].departuresThisWeek = 0
                if routes[r].legs[l].departuresLastWeek == 0 { routes[r].legs[l].maturity = max(Tuning.minimumMaturity, routes[r].legs[l].maturity - 0.15) }
            }
        }
        weeklyOperations()
    }

    mutating func monthlyUpdate() {
        market.fuelIndex = min(1.8, max(0.6, market.fuelIndex + (1.0 - market.fuelIndex) * 0.2 + rng.uniform(-0.08, 0.08)))

        for i in aircraft.indices {
            if case .leased(let monthly, _) = aircraft[i].ownership { spendOnOverhead(monthly) }
        }

        var l = 0
        while l < airline.loans.count {
            let interest = Int((Double(airline.loans[l].remaining) * airline.loans[l].annualRate / 12.0).rounded())
            let principal = min(airline.loans[l].remaining, airline.loans[l].monthlyPrincipal)
            spendOnOverhead(interest)
            airline.cash -= principal
            airline.loans[l].remaining -= principal
            airline.loans[l].monthsLeft -= 1
            if airline.loans[l].remaining <= 0 || airline.loans[l].monthsLeft <= 0 {
                airline.cash -= airline.loans[l].remaining
                airline.loans.remove(at: l)
            } else {
                l += 1
            }
        }

        for r in routes.indices {
            routes[r].revenueLastMonth = routes[r].revenueThisMonth
            routes[r].costLastMonth = routes[r].costThisMonth
            routes[r].revenueThisMonth = 0
            routes[r].costThisMonth = 0
        }
        monthlyOperations()
    }

    /// Weather closes remote airports for a day or three now and then; flights to or from them wait.
    mutating func updateClosures() {
        market.closures.removeAll { $0.untilMinute <= clock.minute }
        // A weather notice goes from the inbox once the airport is open again.
        let now = clock.minute
        issues.removeAll { if case .weather(_, let until) = $0.kind { return until <= now } else { return false } }
        guard ops.mode.hasWeather else { return }
        for code in Set(routes.flatMap { $0.stops }).sorted() {
            guard let airport = AirportCatalog.airport(code) else { continue }
            let chance = (airport.surface == .paved && airport.kind != .small) ? 0.004 : 0.012
            if rng.chance(chance) && !market.closures.contains(where: { $0.airport == code }) {
                let until = clock.minute + rng.int(1...3) * GameClock.minutesPerDay
                market.closures.append(Closure(airport: code, untilMinute: until))
                addNews(.weather, subject: code, amount: until)
                raise(.weather(airport: code, untilMinute: until), options: [IssueOption(choice: .acknowledge, costUSD: 0, days: 0)])
            }
        }
    }

    /// At midnight: another day past the overdraft limit, and the bank closes the airline after `Tuning.daysOverdrawnBeforeBankruptcy`
    /// of them. The overdraft notice comes on the first day and again on each of the last `Tuning.overdraftWarningDays`; the player
    /// can always put it aside and keep flying while they sell, borrow or cut (see `overdraftOptions`).
    mutating func checkMoney() {
        guard airline.cash < -Tuning.overdraftLimit && !ops.mode.unlimitedMoney else {
            settleOverdraft()
            return
        }
        daysOverdrawn += 1
        if daysOverdrawn >= Tuning.daysOverdrawnBeforeBankruptcy {
            isBankrupt = true
            raise(.bankruptcy, options: [IssueOption(choice: .acknowledge, costUSD: 0, days: 0)])
            return
        }
        let alreadyRaised = issues.contains { if case .overdraft = $0.kind { return true } else { return false } }
        let warn = daysOverdrawn == 1 || Tuning.daysOverdrawnBeforeBankruptcy - daysOverdrawn <= Tuning.overdraftWarningDays
        if !alreadyRaised && warn { raise(.overdraft, options: overdraftOptions()) }
    }

    /// The choices on the overdraft notice: an emergency loan when the airline may still borrow enough, putting the notice aside
    /// (the days keep counting), or closing the airline.
    func overdraftOptions() -> [IssueOption] {
        var options = [IssueOption(choice: .acknowledge, costUSD: 0, days: 0), IssueOption(choice: .declareBankruptcy, costUSD: 0, days: 0)]
        if emergencyLoanOffer > 0 { options.insert(IssueOption(choice: .emergencyLoan, costUSD: 0, days: 0), at: 0) }
        return options
    }

    /// Days left before the bank closes the airline while it stays past the overdraft limit; nil when it is not overdrawn.
    public var overdraftDaysLeft: Int? {
        guard daysOverdrawn > 0 else { return nil }
        return max(0, Tuning.daysOverdrawnBeforeBankruptcy - daysOverdrawn)
    }

    /// Once cash is back within the overdraft limit, the overdraft is over: the count of days starts again and the notice goes.
    /// Runs at midnight and after the actions that bring cash in (selling a route, leaving an airport, an emergency loan);
    /// the app may call it after any other.
    public mutating func settleOverdraft() {
        guard airline.cash >= -Tuning.overdraftLimit || ops.mode.unlimitedMoney else { return }
        daysOverdrawn = 0
        issues.removeAll { if case .overdraft = $0.kind { return true } else { return false } }
    }

    /// The certificate is announced once; buying it is a separate step (Money screen, or the button on the notice), so the notice's
    /// own choice costs nothing.
    mutating func checkCertificate() {
        guard let r = nextLevelRequirement, Progression.meets(r, airline: airline), announcedLevel < r.level else { return }
        announcedLevel = r.level
        raise(.certificateReady(level: r.level), options: [IssueOption(choice: .acknowledge, costUSD: 0, days: 0)])
    }
}
