import Foundation
import Testing
import CoreCatalog
@testable import CoreWorld

/// Rewards for watching an ad: what each one gives, its caps, and that sandbox and old saves are handled.
@Suite struct RewardsTests {
    /// A real day (days since 2000-01-01), as the app would pass it.
    static let day = 9_775

    /// True when the change throws. Mutating calls stay outside #expect.
    func refused(_ change: () throws -> Void) -> Bool {
        do {
            try change()
            return false
        } catch {
            return true
        }
    }

    @Test func aProfitDayFollowsTheLastSevenDaysWithAFloor() throws {
        var w = try Fixtures.world()
        w.books = []
        #expect(w.rewardProfitDay == Tuning.rewardProfitDayFloor)
        w.books = (0..<10).map { DayBook(day: $0, revenue: $0 < 3 ? 0 : 20_000, flightCosts: 8_000, overhead: 2_000) }
        #expect(w.rewardProfitDay == 10_000, "only the last 7 days count")
        w.books = (0..<7).map { DayBook(day: $0, revenue: 1_000, flightCosts: 3_000, overhead: 0) }
        #expect(w.rewardProfitDay == Tuning.rewardProfitDayFloor, "a losing airline still gets the floor")
    }

    @Test func theAwayProfitIsPaidAgainUpToTwoProfitDaysThreeTimesADay() throws {
        var w = try Fixtures.world()
        w.books = []
        let most = 2 * Tuning.rewardProfitDayFloor
        #expect(w.rewardOffer(.awayDouble, realDay: Self.day, target: 1_500)?.cash == 1_500)
        #expect(w.rewardOffer(.awayDouble, realDay: Self.day, target: 50_000)?.cash == most)
        #expect(w.rewardOffer(.awayDouble, realDay: Self.day, target: 0) == nil, "nothing to pay again after a loss")
        let noTarget = refused { try w.grantReward(.awayDouble, realDay: Self.day) }
        #expect(noTarget)

        let cash = w.airline.cash
        let revenue = w.airline.stats.revenue
        let booked = w.today.revenue
        try w.grantReward(.awayDouble, realDay: Self.day, target: 50_000)
        #expect(w.airline.cash == cash + most)
        #expect(w.airline.stats.revenue == revenue + most, "booked as revenue")
        #expect(w.today.revenue == booked + most, "and shows in today's books")

        try w.grantReward(.awayDouble, realDay: Self.day, target: 1_000)
        try w.grantReward(.awayDouble, realDay: Self.day, target: 1_000)
        #expect(w.rewardOffer(.awayDouble, realDay: Self.day, target: 1_000) == nil, "three a day")
        let fourth = refused { try w.grantReward(.awayDouble, realDay: Self.day, target: 1_000) }
        #expect(fourth)

        #expect(w.rewardOffer(.awayDouble, realDay: Self.day + 1, target: 1_000)?.leftToday == 3, "the cap resets the next real day")
        try w.grantReward(.awayDouble, realDay: Self.day + 1, target: 1_000)
        #expect(w.rewardsTaken(.awayDouble, realDay: Self.day + 1) == 1)
        #expect(w.rewardsTaken(.awayDouble, realDay: Self.day) == 0, "only the current real day is kept")
    }

    @Test func theSponsorPaysAQuarterOfRouteRevenueAndStacksToFourDays() throws {
        var w = try Fixtures.flyingWorld()
        Fixtures.light(&w, "YUB")
        w.setPausePolicy(.never)
        w.advance(byMinutes: 2 * 1440)
        for _ in 0..<4 { try w.grantReward(.sponsorBoost, realDay: Self.day) }
        #expect(w.sponsorDaysLeft == Tuning.sponsorMaxDays)
        #expect(w.rewardOffer(.sponsorBoost, realDay: Self.day) == nil, "four a day")
        #expect(w.rewardOffer(.sponsorBoost, realDay: Self.day + 1) == nil, "and never more than four days in hand")

        w.advance(byMinutes: 1440)
        let yesterday = w.routes.reduce(0) { $0 + ($1.book.pastDays.last?.revenue ?? 0) }
        #expect(w.sponsorDaysLeft == 3)
        #expect(yesterday > 0)
        #expect(w.lastSponsorPayment == Int((Double(yesterday) * Tuning.sponsorRevenueShare).rounded()))

        try w.grantReward(.sponsorBoost, realDay: Self.day + 1)
        #expect(w.sponsorDaysLeft == 4)
        w.advance(byMinutes: 6 * 1440)
        #expect(w.sponsorDaysLeft == 0, "it runs out")
    }

    @Test func theSponsorPaysOnTopWithoutChangingTheRoutes() throws {
        var a = try Fixtures.flyingWorld()
        Fixtures.light(&a, "YUB")
        a.setPausePolicy(.never)
        a.advance(byMinutes: 1440)
        var b = a
        try b.grantReward(.sponsorBoost, realDay: Self.day)
        a.advance(byMinutes: 1440)
        b.advance(byMinutes: 1440)
        #expect(a.routes[0].sinceOpened.revenue == b.routes[0].sinceOpened.revenue, "fares and demand are the same")
        #expect(b.lastSponsorPayment > 0)
        #expect(b.airline.cash - a.airline.cash == b.lastSponsorPayment)
    }

    @Test func anAircraftInTheHangarComesOutNowThreeTimesADay() throws {
        var w = try Fixtures.world()
        let id = w.aircraft[0].id
        #expect(w.rewardOffer(.instantCheck, realDay: Self.day, target: id) == nil, "not in the hangar")
        for _ in 0..<3 {
            w.aircraft[0].condition = 50
            let until = w.clock.minute + 3 * 1440
            w.aircraft[0].status = .maintenance(until: until)
            #expect(w.rewardOffer(.instantCheck, realDay: Self.day, target: id)?.days == 3)
            try w.grantReward(.instantCheck, realDay: Self.day, target: id)
            #expect(w.aircraft[0].status == .idle)
            #expect(w.aircraft[0].condition >= Tuning.conditionAfterCheck)
        }
        let until = w.clock.minute + 3 * 1440
        w.aircraft[0].status = .maintenance(until: until)
        #expect(w.rewardOffer(.instantCheck, realDay: Self.day, target: id) == nil, "three a day")
        #expect(w.rewardOffer(.instantCheck, realDay: Self.day + 1, target: id) != nil, "more the next real day")
    }

    @Test func aRestorationFinishesNowAndIsRecordedSo() throws {
        var w = try Fixtures.world()
        let id = w.aircraft[0].id
        let until = w.clock.minute + 20 * 1440
        w.aircraft[0].restoration = Restoration(untilMinute: until)
        w.markHeavyCheck(0, until: until)
        w.aircraft[0].status = .maintenance(until: until)
        try w.grantReward(.instantCheck, realDay: Self.day, target: id)
        let now = w.clock.minute
        #expect(w.aircraft[0].restoration?.untilMinute == now)
        #expect(w.aircraft[0].lastHeavyCheckMinute == now)
        #expect(!w.aircraft[0].awaitingRestoration)
        #expect(w.aircraft[0].status == .idle)
    }

    @Test func aMetWeeklyGoalPaysItsBonusAgainOnce() throws {
        var w = try Fixtures.world()
        #expect(w.rewardOffer(.doubleGoalBonus, realDay: Self.day) == nil, "the goal is not met yet")
        w.ops.weeklyGoal?.done = true
        let reward = try #require(w.ops.weeklyGoal?.reward)
        #expect(w.rewardOffer(.doubleGoalBonus, realDay: Self.day)?.cash == reward)
        let cash = w.airline.cash
        try w.grantReward(.doubleGoalBonus, realDay: Self.day)
        #expect(w.airline.cash == cash + reward)
        #expect(w.rewardOffer(.doubleGoalBonus, realDay: Self.day + 1) == nil, "once per goal")
    }

    @Test func theOverdraftSponsorPaysAWeekOfFixedCostsOncePerOverdraft() throws {
        var w = try Fixtures.world()
        w.airline.cash = -150_000
        w.checkMoney()
        let issue = try #require(w.issues.first { if case .overdraft = $0.kind { return true } else { return false } })
        let pay = w.overdraftSponsorPayment()
        #expect(pay >= Tuning.rewardProfitDayFloor)
        #expect(w.rewardOffer(.overdraftSponsor, realDay: Self.day, target: issue.id)?.cash == pay)
        try w.grantReward(.overdraftSponsor, realDay: Self.day, target: issue.id)
        #expect(w.airline.cash == -150_000 + pay)
        #expect(w.issueIndex(issue.id) != nil, "still too deep: the loan choice stays")
        #expect(w.rewardOffer(.overdraftSponsor, realDay: Self.day + 1) == nil, "once per overdraft")

        var near = try Fixtures.world()
        near.airline.cash = -100_500
        near.checkMoney()
        #expect(near.isPausedByIssue)
        try near.grantReward(.overdraftSponsor, realDay: Self.day)
        #expect(!near.isPausedByIssue, "back within the limit: the overdraft notice goes")
    }

    @Test func theMechanicFliesInFreeOncePerBreakdown() throws {
        var w = try Fixtures.world()
        let type = try #require(w.aircraft[0].type)
        w.raiseBreakdown(aircraftIndex: 0, type: type)
        let issue = try #require(w.issues.first { if case .breakdown = $0.kind { return true } else { return false } })
        let mechanic = try #require(issue.options.first { $0.choice == .flyInMechanic })
        let offer = try #require(w.rewardOffer(.freeMechanic, realDay: Self.day, target: issue.id))
        #expect(offer.cash == mechanic.costUSD && offer.days == mechanic.days)
        let cash = w.airline.cash
        try w.grantReward(.freeMechanic, realDay: Self.day, target: issue.id)
        #expect(w.airline.cash == cash, "the bill is waived")
        #expect(w.issueIndex(issue.id) == nil)
        #expect(w.aircraft[0].status == .maintenance(until: w.clock.minute + mechanic.days * 1440))
        let again = refused { try w.grantReward(.freeMechanic, realDay: Self.day, target: issue.id) }
        #expect(again)
    }

    @Test func oneJobADayHasItsPayDoubled() throws {
        var w = try Fixtures.world()
        var made: [Job] = []
        for kind in [JobKind.freight, .mail, .fuelDrums, .crewChange, .freight, .mail, .freight, .mail] {
            if let job = w.makeJob(kind: kind) { made.append(job) }
        }
        try #require(made.count >= 2)
        w.ops.jobs = made
        let first = made[0]
        let second = made[1]
        #expect(w.rewardOffer(.doubleJobPay, realDay: Self.day, target: first.id)?.cash == first.pay)
        try w.grantReward(.doubleJobPay, realDay: Self.day, target: first.id)
        #expect(w.ops.jobs.first { $0.id == first.id }?.pay == first.pay * 2)
        #expect(w.rewardOffer(.doubleJobPay, realDay: Self.day, target: second.id) == nil, "one a day")
        #expect(w.rewardOffer(.doubleJobPay, realDay: Self.day + 1, target: first.id) == nil, "a job is doubled once")
        #expect(w.rewardOffer(.doubleJobPay, realDay: Self.day + 1, target: second.id) != nil)
    }

    @Test func newJobsReplaceTheOpenOffersOnceADay() throws {
        var w = try Fixtures.world()
        var made: [Job] = []
        for kind in [JobKind.freight, .mail, .fuelDrums, .crewChange, .freight, .mail, .freight, .mail] {
            if let job = w.makeJob(kind: kind) { made.append(job) }
        }
        try #require(made.count >= 2)
        let planeID = w.aircraft[0].id
        made[0].aircraftID = planeID
        w.ops.jobs = made
        let takenID = made[0].id
        let openIDs = made.dropFirst().map(\.id)
        try w.grantReward(.newJobs, realDay: Self.day)
        #expect(w.ops.jobs.contains { $0.id == takenID }, "a job being flown stays")
        #expect(!w.ops.jobs.contains { openIDs.contains($0.id) }, "the old offers are gone")
        #expect(w.ops.jobs.count > 1, "and new ones are up")
        #expect(w.rewardOffer(.newJobs, realDay: Self.day) == nil, "once a day")
    }

    @Test func aFreePostersCampaignCostsNothingAndComesEveryTwoWeeks() throws {
        var w = try Fixtures.flyingWorld()
        // The first route starts fully known; make it less known so the campaign has something to raise.
        for l in w.routes[0].legs.indices { w.routes[0].legs[l].maturity = 0.7 }
        let cash = w.airline.cash
        let known = w.routes[0].legs[0].maturity
        try w.grantReward(.freePosters, realDay: Self.day)
        #expect(w.airline.cash == cash, "free")
        #expect(w.activeCampaign(.posters) != nil)
        #expect(w.routes[0].legs[0].maturity > known)
        #expect(w.rewardOffer(.freePosters, realDay: Self.day + 1) == nil, "one is running")
        w.ops.campaigns = []
        #expect(w.rewardOffer(.freePosters, realDay: Self.day + 1) == nil, "once per 14 game days")
        let longAgo = w.clock.dayIndex - Tuning.freePostersEveryDays
        w.ops.rewards.postersDay = longAgo
        #expect(w.rewardOffer(.freePosters, realDay: Self.day + 1) != nil)
    }

    @Test func aRareFindIsHeldSevenMoreDaysOnce() throws {
        var w = try Fixtures.world()
        let added = w.addRareFind(.barnFind)
        let id = try #require(added)
        let until = try #require(w.market.listings.first { $0.id == id }?.rareUntilDay)
        try w.grantReward(.holdRareFind, realDay: Self.day, target: id)
        #expect(w.market.listings.first { $0.id == id }?.rareUntilDay == until + Tuning.rareFindHoldDays)
        #expect(w.rewardOffer(.holdRareFind, realDay: Self.day + 1, target: id) == nil, "once per listing")
        let plain = try #require(w.market.listings.first { $0.rare == nil })
        #expect(w.rewardOffer(.holdRareFind, realDay: Self.day, target: plain.id) == nil, "only rare finds")
    }

    @Test func theBrokersTipAddsTwoListingsUntilMonday() throws {
        var w = try Fixtures.world()
        w.setPausePolicy(.never)
        var copy = w
        let count = w.market.listings.count
        try w.grantReward(.brokersTip, realDay: Self.day)
        try copy.grantReward(.brokersTip, realDay: Self.day)
        #expect(w.market.listings == copy.market.listings, "the same world gets the same tip")
        #expect(w.market.listings.count == count + Tuning.brokerListingCount)
        let ids = w.ops.rewards.brokerListingIDs
        #expect(ids.count == Tuning.brokerListingCount)
        #expect(w.rewardOffer(.brokersTip, realDay: Self.day + 1) == nil, "once a game week")

        let monday = w.ops.rewards.brokerUntilDay
        #expect(monday > w.clock.dayIndex && (monday + 4) % 7 == 0, "next Monday")
        w.advance(toMinute: monday * 1440 + 60)
        #expect(!w.market.listings.contains { ids.contains($0.id) }, "gone with the weekly turnover")
        #expect(w.ops.rewards.brokerListingIDs.isEmpty)
        #expect(w.rewardOffer(.brokersTip, realDay: Self.day + 1) != nil, "a new week, a new tip")
    }

    @Test func sandboxAndAFinishedGameOfferNothing() throws {
        var sandbox = try Fixtures.world(mode: .sandbox)
        for kind in RewardKind.allCases {
            #expect(sandbox.rewardOffer(kind, realDay: Self.day, target: 1) == nil, "\(kind.rawValue)")
        }
        let cash = sandbox.airline.cash
        let paid = refused { try sandbox.grantReward(.awayDouble, realDay: Self.day, target: 1_000) }
        #expect(paid)
        #expect(sandbox.airline.cash == cash)

        var over = try Fixtures.world()
        over.isBankrupt = true
        #expect(over.rewardOffer(.awayDouble, realDay: Self.day, target: 1_000) == nil)
    }

    @Test func rewardStateSurvivesASaveAndOldSavesLoadWithout() throws {
        var w = try Fixtures.flyingWorld()
        try w.grantReward(.sponsorBoost, realDay: Self.day)
        let data = try Fixtures.encode(w)
        let loaded = try JSONDecoder().decode(World.self, from: data)
        #expect(loaded.ops.rewards == w.ops.rewards)
        #expect(loaded.sponsorDaysLeft == 1)

        let old = try JSONDecoder().decode(Operations.self, from: Data(#"{"mode":"normal","goalsCompleted":3}"#.utf8))
        #expect(old.rewards == RewardState())
        #expect(old.goalsCompleted == 3)

        let partial = try JSONDecoder().decode(RewardState.self, from: Data(#"{"sponsorDays":2}"#.utf8))
        #expect(partial.sponsorDays == 2 && partial.realDay == -1 && partial.counts.isEmpty && partial.goalWeek == nil)
    }
}
