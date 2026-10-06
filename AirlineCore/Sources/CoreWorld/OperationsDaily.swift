// CoreWorld/OperationsDaily.swift: the added systems' part of the midnight, weekly and monthly updates (see DailyUpdate.swift).

extension World {
    mutating func dailyOperations() {
        ops.slotsUsedToday = []
        dailyFuelMarket()
        let upkeep = baseUpkeepPerDay
        if upkeep > 0 { spendOnOverhead(upkeep) }
        // Salaries are paid a day at a time, so hiring after payday or letting someone go just before it saves nothing.
        let salaries = salariesPerDay
        if salaries > 0 { spendOnOverhead(salaries) }
        dailyPilots()
        // The real calendar (RealDay.swift) before the board is cleared, so dispatch and event jobs stay on it.
        dailyRealCalendar()
        dailyJobs()
        checkScenario()
        checkWeeklyGoal()
        checkMissedDepartures()
        endCampaigns()
        // Rewards from ads (RewardGrants.swift): the sponsor's payment for the day just closed, the broker's listings leaving.
        dailyRewards()
        if ops.mode.unlimitedMoney && airline.cash < Tuning.sandboxCashFloor { airline.cash += Tuning.sandboxTopUp }
    }

    mutating func weeklyOperations() {
        // Reputation's week closes on the on-time record before it is aged, and the next one starts after (Reputation.swift).
        closeReputationWeek()
        ops.onTime.onTime *= OnTimeRecord.weeklyKeep
        ops.onTime.late *= OnTimeRecord.weeklyKeep
        openReputationWeek()
        weeklyEvents()
        weeklyPilots()
        refreshConnections()
        weeklyRivals()
        checkWeeklyGoal()
        startWeeklyGoal()
        weeklyStaff()
    }

    mutating func monthlyOperations() {
        monthlyRivals()
    }

    /// Pilot and staff salaries for one day (`pilotPayroll` and `staffPayroll` are a month's worth).
    public var salariesPerDay: Int {
        Int((Double(pilotPayroll + staffPayroll) * 12.0 / 365.0).rounded())
    }
}
