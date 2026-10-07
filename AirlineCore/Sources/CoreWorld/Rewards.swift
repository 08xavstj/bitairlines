// CoreWorld/Rewards.swift: rewards for watching an ad (docs/rewarded-ads.md). Never forced: the app shows an offer only when
// `rewardOffer` returns one and an ad is ready, and calls `grantReward` (RewardGrants.swift) once the ad network says the player
// earned it. Cash rewards are sized to the airline (a "profit day") and go to the bank, not to revenue (`payRewardCash`), so
// ads never count toward a certificate level or a revenue goal. Each kind has a cap per real day:
// Core has no clock, so the app passes the real day in (days since 2000-01-01 on the player's calendar). Some kinds also have
// a limit in game time or per thing (per overdraft, per breakdown, per listing, per weekly goal).
// Sandbox has no rewards: money never runs out there, so there is nothing to win.
// The state is one value in Operations (`ops.rewards`), decoded with decodeIfPresent, so older saves load.
import CoreCatalog
import CoreSim

public enum RewardKind: String, Sendable, Hashable, Codable, CaseIterable {
    /// The profit made while the player was away, paid again (up to `Tuning.awayRewardProfitDays` profit days). `target` is
    /// that profit in dollars.
    case awayDouble
    /// A sponsor pays a share of a game day's route revenue, for one more game day (stacks up to a limit).
    case sponsorBoost
    /// An aircraft in the hangar (a check, a repair or a restoration) comes out now. `target` is the aircraft id.
    case instantCheck
    /// This week's goal bonus, paid again once the goal is met (or last week's, until this week's is met).
    case doubleGoalBonus
    /// While overdrawn: a sponsor pays a week of the airline's fixed costs. `target`, if given, is the overdraft issue id.
    case overdraftSponsor
    /// A breakdown: the mechanic flies in free. `target` is the breakdown issue id.
    case freeMechanic
    /// One job's pay doubled. `target` is the job id.
    case doubleJobPay
    /// A posters campaign at no cost.
    case freePosters
    /// The open offers on the job board replaced with new ones.
    case newJobs
    /// A rare find stays on the market longer. `target` is the listing id.
    case holdRareFind
    /// Extra used aircraft for sale until the next weekly turnover.
    case brokersTip

    /// True when `grantReward` needs a `target` (an amount for awayDouble, an id for the others).
    public var needsTarget: Bool {
        switch self {
        case .awayDouble, .instantCheck, .freeMechanic, .doubleJobPay, .holdRareFind: return true
        case .sponsorBoost, .doubleGoalBonus, .overdraftSponsor, .freePosters, .newJobs, .brokersTip: return false
        }
    }
}

/// What a reward would give now: numbers only, the app writes the words.
public struct RewardOffer: Sendable, Hashable {
    public var kind: RewardKind
    /// Cash: paid now (awayDouble, doubleGoalBonus, overdraftSponsor), the extra pay (doubleJobPay), the bill waived
    /// (freeMechanic), the campaign's price (freePosters), or the sponsor's payment for a day like yesterday (sponsorBoost).
    public var cash: Int
    /// Game days: sponsor days after this watch, hangar days saved, campaign days, extra days on the market.
    public var days: Int
    /// Things added: used aircraft for brokersTip, jobs tried for newJobs.
    public var count: Int
    /// How many more times it can be taken this real day; nil when the kind has no daily cap.
    public var leftToday: Int?
}

/// What has been taken, for the caps. Lives in Operations.
public struct RewardState: Sendable, Hashable, Codable {
    /// The real day `counts` belong to; a new day starts from zero.
    public var realDay = -1
    /// Rewards taken on `realDay`, by kind name.
    public var counts: [String: Int] = [:]
    /// Game days of sponsor boost still to pay, and the last payment (to show).
    public var sponsorDays = 0
    public var lastSponsorPay = 0
    /// The weekly goal (its week number) whose bonus was doubled.
    public var goalWeek: Int?
    /// Game day of the last free posters campaign.
    public var postersDay: Int?
    /// Game week of the last broker's tip, its listings and the day they leave the market.
    public var brokerWeek: Int?
    public var brokerListingIDs: [Int] = []
    public var brokerUntilDay = 0
    /// Things already rewarded once: rare finds held, overdraft issues sponsored, jobs doubled (the last few of each).
    public var heldListingIDs: [Int] = []
    public var overdraftIssueIDs: [Int] = []
    public var doubledJobIDs: [Int] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        realDay = try c.decodeIfPresent(Int.self, forKey: .realDay) ?? -1
        counts = try c.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
        sponsorDays = try c.decodeIfPresent(Int.self, forKey: .sponsorDays) ?? 0
        lastSponsorPay = try c.decodeIfPresent(Int.self, forKey: .lastSponsorPay) ?? 0
        goalWeek = try c.decodeIfPresent(Int.self, forKey: .goalWeek)
        postersDay = try c.decodeIfPresent(Int.self, forKey: .postersDay)
        brokerWeek = try c.decodeIfPresent(Int.self, forKey: .brokerWeek)
        brokerListingIDs = try c.decodeIfPresent([Int].self, forKey: .brokerListingIDs) ?? []
        brokerUntilDay = try c.decodeIfPresent(Int.self, forKey: .brokerUntilDay) ?? 0
        heldListingIDs = try c.decodeIfPresent([Int].self, forKey: .heldListingIDs) ?? []
        overdraftIssueIDs = try c.decodeIfPresent([Int].self, forKey: .overdraftIssueIDs) ?? []
        doubledJobIDs = try c.decodeIfPresent([Int].self, forKey: .doubledJobIDs) ?? []
    }
}

// MARK: Rewards
extension Tuning {
    /// A profit day: the average daily operating result over this many game days, never below the floor.
    public static let rewardProfitDayWindow = 7
    public static let rewardProfitDayFloor = 2_000
    /// The away profit is paid again up to this many profit days. It matches the longest break the app pays out
    /// (AwayReport.maxGameMinutes, three game days), so a full break is usually paid again in full.
    public static let awayRewardProfitDays = 3
    /// The sponsor pays this share of a game day's route revenue, for at most this many game days in hand.
    public static let sponsorRevenueShare = 0.25
    public static let sponsorMaxDays = 4
    /// The overdraft sponsor pays this many days of the airline's fixed costs (head office and aircraft).
    public static let overdraftSponsorDays = 7
    /// A free posters campaign at most this often (game days).
    public static let freePostersEveryDays = 14
    /// Extra days a held rare find stays on the market.
    public static let rareFindHoldDays = 7
    /// The broker's tip: this many extra listings, priced at this share of their value.
    public static let brokerListingCount = 2
    public static let brokerPriceLow = 0.90
    public static let brokerPriceHigh = 1.00
    /// How many rewarded ids are remembered per list.
    public static let rewardIDsKept = 50

    /// The most of each reward per real day; nil when only its own limit applies (per overdraft, breakdown or listing).
    public static func rewardDailyCap(_ kind: RewardKind) -> Int? {
        switch kind {
        case .awayDouble: return 3
        case .sponsorBoost: return 4
        case .instantCheck: return 3
        case .doubleGoalBonus, .doubleJobPay, .freePosters, .newJobs, .brokersTip: return 1
        case .overdraftSponsor, .freeMechanic, .holdRareFind: return nil
        }
    }
}

extension World {
    /// The average daily operating result over the last few game days, at least the floor. Cash rewards are sized by it.
    public var rewardProfitDay: Int {
        let days = books.suffix(Tuning.rewardProfitDayWindow)
        guard !days.isEmpty else { return Tuning.rewardProfitDayFloor }
        let average = days.reduce(0) { $0 + $1.net } / days.count
        return max(Tuning.rewardProfitDayFloor, average)
    }

    /// Game days of sponsor boost still to be paid, and the last payment.
    public var sponsorDaysLeft: Int { ops.rewards.sponsorDays }
    public var lastSponsorPayment: Int { ops.rewards.lastSponsorPay }

    /// How many of this reward were taken on this real day.
    public func rewardsTaken(_ kind: RewardKind, realDay: Int) -> Int {
        let log = ops.rewards
        return log.realDay == realDay ? log.counts[kind.rawValue] ?? 0 : 0
    }

    /// What this reward would give now, or nil when it is not on offer (capped, nothing to apply it to, sandbox, game over).
    /// `target` narrows it to one aircraft, issue, job or listing (or is the away profit, for awayDouble).
    public func rewardOffer(_ kind: RewardKind, realDay: Int, target: Int? = nil) -> RewardOffer? {
        // The latest real day this game has seen counts (RealDay.swift): a clock set back opens no cap again.
        let realDay = rewardDay(realDay)
        guard !ops.mode.unlimitedMoney, !isBankrupt else { return nil }
        var left: Int?
        if let cap = Tuning.rewardDailyCap(kind) {
            let remaining = cap - rewardsTaken(kind, realDay: realDay)
            guard remaining > 0 else { return nil }
            left = remaining
        }
        var offer = RewardOffer(kind: kind, cash: 0, days: 0, count: 0, leftToday: left)
        let log = ops.rewards
        switch kind {
        case .awayDouble:
            let most = rewardProfitDay * Tuning.awayRewardProfitDays
            if let target {
                guard target > 0 else { return nil }
                offer.cash = min(target, most)
            } else {
                offer.cash = most
            }
        case .sponsorBoost:
            guard !routes.isEmpty, log.sponsorDays < Tuning.sponsorMaxDays else { return nil }
            offer.cash = sponsorPayment()
            offer.days = log.sponsorDays + 1
        case .instantCheck:
            guard let i = hangarAircraftIndex(target), case .maintenance(let until) = aircraft[i].status else { return nil }
            offer.days = (until - clock.minute + GameClock.minutesPerDay - 1) / GameClock.minutesPerDay
        case .doubleGoalBonus:
            guard let paid = goalToDouble, log.goalWeek != paid.week else { return nil }
            offer.cash = paid.reward
        case .overdraftSponsor:
            guard let k = overdraftIssueIndex(), target == nil || issues[k].id == target,
                  !log.overdraftIssueIDs.contains(issues[k].id) else { return nil }
            offer.cash = overdraftSponsorPayment()
            offer.days = Tuning.overdraftSponsorDays
        case .freeMechanic:
            guard let k = breakdownIssueIndex(target),
                  let option = issues[k].options.first(where: { $0.choice == .flyInMechanic }) else { return nil }
            offer.cash = option.costUSD
            offer.days = option.days
        case .doubleJobPay:
            let doubled = log.doubledJobIDs
            let found = ops.jobs.first { candidate in
                guard isOnOffer(candidate), !doubled.contains(candidate.id) else { return false }
                return target == nil || candidate.id == target
            }
            guard let found else { return nil }
            offer.cash = found.pay
        case .freePosters:
            guard !routes.isEmpty, activeCampaign(.posters) == nil else { return nil }
            if let last = log.postersDay, clock.dayIndex < last + Tuning.freePostersEveryDays { return nil }
            offer.cash = campaignPrice(.posters)
            offer.days = Tuning.campaignDays(.posters)
        case .newJobs:
            guard ops.jobArea.count >= 2 else { return nil }
            offer.count = jobBoardSize
        case .holdRareFind:
            let held = log.heldListingIDs
            let canHold = market.listings.contains { listing in
                guard listing.rare != nil, listing.rareUntilDay != nil, !held.contains(listing.id) else { return false }
                return target == nil || listing.id == target
            }
            guard canHold else { return nil }
            offer.days = Tuning.rareFindHoldDays
        case .brokersTip:
            guard log.brokerWeek != rewardWeek, !AircraftCatalog.available(atLevel: airline.level).isEmpty else { return nil }
            offer.count = Tuning.brokerListingCount
        }
        return offer
    }

    // MARK: Helpers

    /// The game week (counted from Mondays, as the weekly goals count it).
    var rewardWeek: Int { (clock.dayIndex - clock.weekday + 7) / 7 }

    /// Revenue the routes booked on the last finished game day.
    func routeRevenueYesterday() -> Int { routes.reduce(0) { $0 + ($1.book.pastDays.last?.revenue ?? 0) } }

    /// What the sponsor pays for one game day: a share of the last finished day's route revenue.
    func sponsorPayment() -> Int { Int((Double(routeRevenueYesterday()) * Tuning.sponsorRevenueShare).rounded()) }

    /// A week of fixed costs (head office and each delivered aircraft, as charged at midnight), at least the floor.
    func overdraftSponsorPayment() -> Int {
        var fixed = Tuning.headOfficePerDay(level: airline.level)
        for plane in aircraft where plane.isDelivered {
            if let type = plane.type { fixed += LegEconomics.fixedPerDay(type: type) }
        }
        return max(Tuning.rewardProfitDayFloor, Int((fixed * Double(Tuning.overdraftSponsorDays)).rounded()))
    }

    /// The aircraft in the hangar (this one, or the first one when `target` is nil).
    func hangarAircraftIndex(_ target: Int?) -> Int? {
        let now = clock.minute
        return aircraft.indices.first { i in
            guard target == nil || aircraft[i].id == target else { return false }
            if case .maintenance(let until) = aircraft[i].status { return until > now }
            return false
        }
    }

    /// The breakdown waiting for a decision (this one, or the first one when `target` is nil).
    func breakdownIssueIndex(_ target: Int?) -> Int? {
        issues.indices.first { k in
            guard target == nil || issues[k].id == target else { return false }
            if case .breakdown = issues[k].kind { return true }
            return false
        }
    }

    func overdraftIssueIndex() -> Int? {
        issues.firstIndex { if case .overdraft = $0.kind { return true } else { return false } }
    }
}
