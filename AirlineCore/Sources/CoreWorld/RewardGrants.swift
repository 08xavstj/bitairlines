// CoreWorld/RewardGrants.swift: applying a reward the player earned by watching an ad (see Rewards.swift for the offers and
// caps), and the midnight part: the sponsor's daily payment and the broker's listings leaving. Cash goes to the bank with
// `payRewardCash`, not as revenue, so ads never count toward a certificate level or a revenue goal. Only the broker's listings
// and new jobs draw random numbers, from ops.rng.
import CoreCatalog
import CoreSim

extension World {
    /// Gives the reward and counts it against today's cap. Throws when it is not on offer (see `rewardOffer`) or a
    /// reward that needs a `target` has none.
    public mutating func grantReward(_ kind: RewardKind, realDay: Int, target: Int? = nil) throws {
        if kind.needsTarget && target == nil { throw WorldError.invalidChoice }
        guard let offer = rewardOffer(kind, realDay: realDay, target: target) else { throw WorldError.invalidChoice }
        switch kind {
        case .awayDouble:
            payRewardCash(offer.cash)
        case .sponsorBoost:
            let days = ops.rewards.sponsorDays
            ops.rewards.sponsorDays = min(Tuning.sponsorMaxDays, days + 1)
        case .instantCheck:
            try finishHangarNow(target)
        case .doubleGoalBonus:
            let week = ops.weeklyGoal?.week
            payRewardCash(offer.cash)
            ops.rewards.goalWeek = week
        case .overdraftSponsor:
            try sponsorOverdraft(offer.cash)
        case .freeMechanic:
            try sendFreeMechanic(target)
        case .doubleJobPay:
            guard let target, let j = ops.jobs.firstIndex(where: { $0.id == target }) else { throw WorldError.jobUnavailable }
            let pay = ops.jobs[j].pay
            ops.jobs[j].pay = pay * 2
            let kept = World.keeping(ops.rewards.doubledJobIDs, adding: target)
            ops.rewards.doubledJobIDs = kept
        case .freePosters:
            startFreePosters()
        case .newJobs:
            replaceOpenJobs()
        case .holdRareFind:
            guard let target, let k = market.listings.firstIndex(where: { $0.id == target }) else { throw WorldError.unknownListing(target ?? 0) }
            let until = market.listings[k].rareUntilDay ?? clock.dayIndex
            market.listings[k].rareUntilDay = until + Tuning.rareFindHoldDays
            let kept = World.keeping(ops.rewards.heldListingIDs, adding: target)
            ops.rewards.heldListingIDs = kept
        case .brokersTip:
            addBrokerListings()
        }
        countReward(kind, realDay: realDay)
    }

    /// Midnight, after the route books closed the day: the sponsor pays for that day, and the broker's listings leave once
    /// their week is over. Called from dailyOperations.
    mutating func dailyRewards() {
        let days = ops.rewards.sponsorDays
        if days > 0 {
            let pay = sponsorPayment()
            if pay > 0 { payRewardCash(pay) }
            ops.rewards.sponsorDays = days - 1
            ops.rewards.lastSponsorPay = pay
        }
        let ids = ops.rewards.brokerListingIDs
        if !ids.isEmpty && clock.dayIndex >= ops.rewards.brokerUntilDay {
            market.listings.removeAll { ids.contains($0.id) }
            ops.rewards.brokerListingIDs = []
        }
    }

    // MARK: The rewards

    mutating func countReward(_ kind: RewardKind, realDay: Int) {
        if ops.rewards.realDay != realDay {
            ops.rewards.realDay = realDay
            ops.rewards.counts = [:]
        }
        let taken = ops.rewards.counts[kind.rawValue] ?? 0
        ops.rewards.counts[kind.rawValue] = taken + 1
    }

    /// Reward cash goes into the bank only. It is not revenue: it never counts toward a certificate level, a revenue goal or the
    /// borrowing limit, and it stays out of the day books, so it does not grow the profit day that sizes the next reward. The
    /// weekly goal bonus is paid the same way (WeeklyGoals).
    mutating func payRewardCash(_ amount: Int) {
        airline.cash += amount
    }

    /// The list with the id added, keeping the last few.
    static func keeping(_ ids: [Int], adding id: Int) -> [Int] { Array((ids + [id]).suffix(Tuning.rewardIDsKept)) }

    /// Ends the aircraft's check, repair or restoration now. A heavy check or restoration is put on record as ending now.
    mutating func finishHangarNow(_ target: Int?) throws {
        guard let i = hangarAircraftIndex(target), case .maintenance(let until) = aircraft[i].status else { throw WorldError.invalidChoice }
        let now = clock.minute
        if aircraft[i].restoration?.untilMinute == until { aircraft[i].restoration = Restoration(untilMinute: now) }
        if aircraft[i].heavyCheckMinuteStore == until { aircraft[i].heavyCheckMinuteStore = now }
        finishMaintenance(i)
    }

    /// Pays the sponsor's week. If that brings the bank back within the overdraft limit, the overdraft notice goes.
    mutating func sponsorOverdraft(_ amount: Int) throws {
        guard let k = overdraftIssueIndex() else { throw WorldError.invalidChoice }
        let id = issues[k].id
        payRewardCash(amount)
        let kept = World.keeping(ops.rewards.overdraftIssueIDs, adding: id)
        ops.rewards.overdraftIssueIDs = kept
        if airline.cash >= -Tuning.overdraftLimit {
            daysOverdrawn = 0
            issues.removeAll { if case .overdraft = $0.kind { return true } else { return false } }
        }
    }

    /// Settles a breakdown as the fly-in mechanic, with the bill waived.
    mutating func sendFreeMechanic(_ target: Int?) throws {
        guard let k = breakdownIssueIndex(target), case .breakdown(let planeID) = issues[k].kind,
              let option = issues[k].options.first(where: { $0.choice == .flyInMechanic }) else { throw WorldError.invalidChoice }
        let until = clock.minute + option.days * GameClock.minutesPerDay
        if let i = aircraftIndex(planeID) { aircraft[i].status = .maintenance(until: until) }
        issues.remove(at: k)
    }

    /// Starts a posters campaign as `startCampaign` does, without the bill.
    mutating func startFreePosters() {
        let campaign = Campaign.posters
        let day = clock.dayIndex
        ops.campaigns.append(ActiveCampaign(kind: campaign, untilDay: day + Tuning.campaignDays(campaign)))
        let lift = Tuning.campaignAwareness(campaign)
        for r in routes.indices {
            for l in routes[r].legs.indices { routes[r].legs[l].maturity = min(1.0, routes[r].legs[l].maturity + lift) }
        }
        airline.reputation = min(100, airline.reputation + Tuning.campaignReputation(campaign))
        ops.rewards.postersDay = day
    }

    /// Takes the open offers off the job board and fills it with new ones. Jobs being flown stay, and so do the day's dispatch
    /// and seasonal jobs (they follow the real calendar).
    mutating func replaceOpenJobs() {
        ops.jobs.removeAll { !$0.isTaken && !$0.isSpecial }
        refreshJobArea()
        let size = jobBoardSize
        for _ in 0..<size {
            if let job = makeJob(kind: pickJobKind()) { ops.jobs.append(job) }
        }
    }

    /// Puts the broker's extra aircraft on the market (types the airline may fly now) until next Monday's turnover.
    mutating func addBrokerListings() {
        let types = AircraftCatalog.available(atLevel: airline.level)
        guard !types.isEmpty else { return }
        var ids: [Int] = []
        for _ in 0..<Tuning.brokerListingCount {
            let type = ops.rng.pick(types)
            let age = type.inProduction ? ops.rng.uniform(2, 30) : ops.rng.uniform(25, 75)
            let condition = min(95, max(30, 100 - age + ops.rng.uniform(-12, 8)))
            let value = Double(Valuation.value(type: type, ageYears: age, condition: condition))
            let price = Int((value * ops.rng.uniform(Tuning.brokerPriceLow, Tuning.brokerPriceHigh)).rounded())
            let delivery = ops.rng.int(2...9)
            let id = market.nextListingID
            market.nextListingID += 1
            market.listings.append(UsedListing(id: id, typeID: type.id, ageYears: age, condition: condition, price: price, deliveryDays: delivery))
            ids.append(id)
        }
        let week = rewardWeek
        let monday = clock.dayIndex - clock.weekday + 7
        let before = ops.rewards.brokerListingIDs
        ops.rewards.brokerWeek = week
        ops.rewards.brokerListingIDs = before + ids
        ops.rewards.brokerUntilDay = monday
    }
}
