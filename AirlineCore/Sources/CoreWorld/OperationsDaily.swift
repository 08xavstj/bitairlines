// CoreWorld/OperationsDaily.swift: the added systems' part of the midnight, weekly and monthly updates (see DailyUpdate.swift).

extension World {
    mutating func dailyOperations() {
        ops.slotsUsedToday = []
        dailyFuelMarket()
        let upkeep = baseUpkeepPerDay
        if upkeep > 0 { spendOnOverhead(upkeep) }
        dailyJobs()
        checkScenario()
        checkWeeklyGoal()
        endCampaigns()
        if ops.mode.unlimitedMoney && airline.cash < Tuning.sandboxCashFloor { airline.cash += Tuning.sandboxTopUp }
    }

    mutating func weeklyOperations() {
        ops.onTime.onTime *= OnTimeRecord.weeklyKeep
        ops.onTime.late *= OnTimeRecord.weeklyKeep
        weeklyEvents()
        weeklyPilots()
        refreshConnections()
        weeklyRivals()
        checkWeeklyGoal()
        startWeeklyGoal()
        weeklyStaff()
    }

    mutating func monthlyOperations() {
        let payroll = pilotPayroll
        if payroll > 0 { spendOnOverhead(payroll) }
        if staffPayroll > 0 { spendOnOverhead(staffPayroll) }
        monthlyRivals()
    }
}
