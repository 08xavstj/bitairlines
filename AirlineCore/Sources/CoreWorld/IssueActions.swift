// CoreWorld/IssueActions.swift: raising issues and resolving them.
import CoreCatalog

extension World {
    func pauses(_ issue: Issue) -> Bool {
        switch pausePolicy {
        case .never: false
        case .critical: issue.isCritical
        case .all: true
        }
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
        let hourly = Double(type.maintenanceUSDPerHour) * wear
        let id = nextIssueID
        raise(.breakdown(aircraftID: aircraft[i].id), options: [
            IssueOption(choice: .repairNow, costUSD: Int((hourly * 30).rounded()), days: 1),
            IssueOption(choice: .flyInMechanic, costUSD: Int((hourly * 12).rounded()), days: 3),
            IssueOption(choice: .waitForParts, costUSD: 0, days: 7),
        ])
        aircraft[i].status = .grounded(issue: id)
        airline.reputation = max(0, airline.reputation - 0.8)
        addNews(.breakdown, subject: aircraft[i].registration, amount: aircraft[i].id)
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
            if choice == .emergencyLoan {
                try takeLoan(amount: Tuning.emergencyLoanAmount, annualRate: Tuning.emergencyLoanRate, months: 24)
            } else if choice == .declareBankruptcy {
                isBankrupt = true
            }
        case .certificateReady, .delivery, .weather, .bankruptcy:
            break
        }
        if let again = issueIndex(issueID) { issues.remove(at: again) }
    }
}
