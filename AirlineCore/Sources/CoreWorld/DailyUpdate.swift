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

        for i in aircraft.indices { aircraft[i].blockMinutesToday = 0 }

        if clock.weekday == 0 { weeklyUpdate() }
        if clock.date.day == 1 { monthlyUpdate() }
        updateClosures()
        dailyOperations()
        checkMoney()
        checkCertificate()
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

    mutating func checkMoney() {
        if airline.cash < -Tuning.overdraftLimit && !ops.mode.unlimitedMoney {
            daysOverdrawn += 1
            let alreadyRaised = issues.contains { if case .overdraft = $0.kind { return true } else { return false } }
            if !alreadyRaised {
                var options = [IssueOption(choice: .declareBankruptcy, costUSD: 0, days: 0)]
                if totalDebt + Tuning.emergencyLoanAmount <= borrowingLimit { options.insert(IssueOption(choice: .emergencyLoan, costUSD: 0, days: 0), at: 0) }
                raise(.overdraft, options: options)
            }
            if daysOverdrawn >= Tuning.daysOverdrawnBeforeBankruptcy {
                isBankrupt = true
                raise(.bankruptcy, options: [IssueOption(choice: .acknowledge, costUSD: 0, days: 0)])
            }
        } else {
            daysOverdrawn = 0
            issues.removeAll { if case .overdraft = $0.kind { return true } else { return false } }
        }
    }

    mutating func checkCertificate() {
        guard let r = nextLevelRequirement, Progression.meets(r, airline: airline), announcedLevel < r.level else { return }
        announcedLevel = r.level
        raise(.certificateReady(level: r.level), options: [IssueOption(choice: .acknowledge, costUSD: r.fee, days: 0)])
    }
}
