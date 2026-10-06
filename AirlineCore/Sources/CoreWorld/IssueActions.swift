// CoreWorld/IssueActions.swift: raising issues and resolving them.
import CoreCatalog

extension Tuning {
    /// The overdraft notice comes back (and stops the game) on each of the last this many days before the bank closes the airline.
    public static let overdraftWarningDays = 3
    /// The emergency loan lends enough to bring cash back this far inside the overdraft limit (at least `emergencyLoanAmount`),
    /// rounded up to whole steps.
    public static let emergencyLoanMargin = 50_000
    public static let emergencyLoanStep = 50_000
}

extension World {
    /// Running out of money stops the game whatever the policy, so the airline cannot go bankrupt unseen at high speed.
    func pauses(_ issue: Issue) -> Bool {
        switch issue.kind {
        case .overdraft, .bankruptcy: return true
        default: break
        }
        switch pausePolicy {
        case .never: return false
        case .critical: return issue.isCritical
        case .all: return true
        }
    }

    /// What the emergency loan on the overdraft notice lends now: enough to bring cash back inside the overdraft limit with a
    /// margin, at least `Tuning.emergencyLoanAmount`, never more than the airline may still borrow. 0 when it cannot borrow that much.
    public var emergencyLoanOffer: Int {
        let gap = max(0, -airline.cash - Tuning.overdraftLimit) + Tuning.emergencyLoanMargin
        let step = Tuning.emergencyLoanStep
        let wanted = max(Tuning.emergencyLoanAmount, (gap + step - 1) / step * step)
        let room = borrowingLimit - totalDebt
        if room >= wanted { return wanted }
        return room >= Tuning.emergencyLoanAmount ? room / step * step : 0
    }

    mutating func raise(_ kind: IssueKind, options: [IssueOption]) {
        var issue = Issue(id: takeIssueID(), kind: kind, raisedMinute: clock.minute, pausesGame: false, options: options)
        issue.pausesGame = pauses(issue)
        issues.append(issue)
    }

    /// Changes when the game stops for issues; applies to issues already waiting.
    public mutating func setPausePolicy(_ policy: PausePolicy) {
        pausePolicy = policy
        for i in issues.indices { issues[i].pausesGame = pauses(issues[i]) }
    }

    mutating func raiseBreakdown(aircraftIndex i: Int, type: AircraftType) {
        let wear = Valuation.wearFactor(ageYears: aircraft[i].ageYears(atDay: clock.dayIndex), condition: aircraft[i].condition)
        // Repairs are cheaper where the airline has a hangar, and with the mechanics' perk.
        let hangar = hasHangar(at: aircraft[i].location) ? 0.6 : 1.0
        let hourly = Double(type.maintenanceUSDPerHour) * wear * hangar * maintenanceFactor
        let id = nextIssueID
        raise(.breakdown(aircraftID: aircraft[i].id), options: [
            IssueOption(choice: .repairNow, costUSD: Int((hourly * 30).rounded()), days: 1),
            IssueOption(choice: .flyInMechanic, costUSD: Int((hourly * 12).rounded()), days: 3),
            IssueOption(choice: .waitForParts, costUSD: 0, days: 7),
        ])
        aircraft[i].status = .grounded(issue: id)
        airline.reputation = max(0, airline.reputation - 0.8)
        addNews(.breakdown, subject: aircraft[i].registration, amount: aircraft[i].id)
        settleBreakdown(issueID: id)
    }

    /// Settles an issue with one of its options.
    public mutating func resolve(issueID: Int, choice: IssueChoice) throws {
        guard let ii = issueIndex(issueID) else { throw WorldError.unknownIssue(issueID) }
        let issue = issues[ii]
        guard let option = issue.options.first(where: { $0.choice == choice }) else { throw WorldError.invalidChoice }

        switch issue.kind {
        case .breakdown(let planeID):
            if option.costUSD > 0 && airline.cash < option.costUSD { throw WorldError.notEnoughCash(needed: option.costUSD) }
            airline.cash -= option.costUSD
            airline.stats.expenses += option.costUSD
            today.flightCosts += option.costUSD
            if let i = aircraftIndex(planeID) { aircraft[i].status = .maintenance(until: clock.minute + option.days * GameClock.minutesPerDay) }
        case .overdraft:
            // Put aside (.acknowledge), the notice goes and the clock runs; the days keep counting and it comes back near the end.
            if choice == .emergencyLoan {
                let amount = emergencyLoanOffer
                guard amount > 0 else { throw WorldError.notEnoughCash(needed: Tuning.emergencyLoanAmount) }
                try takeLoan(amount: amount, annualRate: Tuning.emergencyLoanRate, months: 24)
                settleOverdraft()
            } else if choice == .declareBankruptcy {
                isBankrupt = true
            }
        case .certificateReady, .delivery, .weather, .bankruptcy:
            break
        }
        if let again = issueIndex(issueID) { issues.remove(at: again) }
    }
}
