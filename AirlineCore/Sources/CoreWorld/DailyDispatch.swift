// CoreWorld/DailyDispatch.swift: one special charter for each real day, the same for every airline with the same network.
// It is picked from the real day (RealDay.swift) and the airline's served airports with its own seeded stream, so it never
// draws from ops.rng or the world's rng. It is always a job some aircraft in the fleet can fly (JobFit.swift). Flying it earns a
// stamp (one per real day at most, late still counts, in any order); every 7 stamps, in a row or not, unlock a classic livery and
// put a rare find in the hangar. Rewards are looks and leads, not cash.
import CoreCatalog
import CoreSim

/// The stamp card. Stored in Operations; older saves start with an empty card.
public struct DispatchBook: Sendable, Hashable, Codable {
    /// Dispatches flown in this game.
    public var stamps = 0
    /// The real day of the last dispatch that earned a stamp (0 for none).
    public var lastStampDay = 0
    /// The real day the board last got its dispatch (0 for none).
    public var postedDay = 0
    /// Rewards handed out (one per 7 stamps).
    public var rewardsEarned = 0
    /// The real days whose dispatch earned a stamp, oldest first (the last few). Missing from older saves.
    public var stampedDays: [Int] = []

    public init() {}

    enum CodingKeys: String, CodingKey { case stamps, lastStampDay, postedDay, rewardsEarned, stampedDays }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stamps = try c.decodeIfPresent(Int.self, forKey: .stamps) ?? 0
        lastStampDay = try c.decodeIfPresent(Int.self, forKey: .lastStampDay) ?? 0
        postedDay = try c.decodeIfPresent(Int.self, forKey: .postedDay) ?? 0
        rewardsEarned = try c.decodeIfPresent(Int.self, forKey: .rewardsEarned) ?? 0
        stampedDays = try c.decodeIfPresent([Int].self, forKey: .stampedDays) ?? []
    }

    /// True if the dispatch of this real day has earned its stamp.
    public func isStamped(_ day: Int) -> Bool { day > 0 && (day == lastStampDay || stampedDays.contains(day)) }
}

/// What a day's dispatch is: a job kind, a pair of airports, a load and the pay.
public struct DispatchPlan: Sendable, Hashable {
    public var kind: JobKind
    public var from: String
    public var to: String
    public var passengers: Int
    public var cargoKg: Int
    public var pay: Int
}

// MARK: Daily dispatch
extension Tuning {
    /// Stamps for one reward.
    public static let stampsPerReward = 7
    /// How far from a served airport the dispatch goes.
    static let dispatchMinKm = 60.0
    static let dispatchMaxKm = 650.0
    /// The dispatch pays this much more than a board job of the same kind and load.
    static let dispatchPayBoost = 1.3
    /// The least a dispatch pays, by certificate level 1...7.
    static let dispatchMinPayByLevel = [4_000, 8_000, 16_000, 32_000, 64_000, 125_000, 250_000]
    /// The kinds a dispatch can be.
    static let dispatchKinds: [JobKind] = [.medevac, .mail, .fuelDrums, .lodgeCharter, .crewChange]
    /// A dispatch or seasonal job stays offered at least this long ahead (game minutes), renewed each game day while it lasts.
    static let specialJobOpenMinutes = 2 * GameClock.minutesPerDay
    /// ...and must land within this long of being taken (or of the last renewal).
    static let specialJobDeadlineMinutes = 3 * GameClock.minutesPerDay
    /// Stamped real days remembered (a dispatch from further back than this can no longer be on the board).
    static let stampedDaysKept = 14

    static func dispatchMinPay(level: Int) -> Int {
        let table = dispatchMinPayByLevel
        return table[min(max(level, 1), table.count) - 1]
    }
}

extension World {
    /// The seed for a real day's dispatch: the same for every player.
    static func dispatchSeed(realDay: Int) -> UInt64 {
        (UInt64(max(0, realDay)) &+ 1) &* 0x9E37_79B9_7F4A_7C15 ^ 0xD15B_A7C4_0000_0001
    }

    /// The dispatch for a real day, worked out from the day and the network (served airports, the area within reach and the
    /// fleet). Only pairs some aircraft in the fleet can fly this month (with a slot to leave the pickup where one is needed), and
    /// the load fits that aircraft. Nil when the network has nowhere suitable yet. Pure: it draws from its own stream, not ops.rng.
    public func dispatchPlan(realDay day: Int) -> DispatchPlan? {
        var served = servedAirports.compactMap { AirportCatalog.airport($0) }
        let area = ops.jobArea.compactMap { AirportCatalog.airport($0) }
        guard !served.isEmpty, area.count >= 2 else { return nil }
        var rng = SeededRandom(seed: World.dispatchSeed(realDay: day))
        let kind = rng.pick(Tuning.dispatchKinds)
        rng.shuffle(&served)
        for anchor in served {
            // A medevac brings a patient in from the outlying place; the rest go out to it.
            let pool = area.filter { place in
                let km = anchor.distanceKm(to: place)
                guard place.code != anchor.code && km >= Tuning.dispatchMinKm && km <= Tuning.dispatchMaxKm else { return false }
                let from = kind == .medevac ? place : anchor
                let to = kind == .medevac ? anchor : place
                return canDepartOnJob(from: from) && jobSizingPlane(kind: kind, from: from, to: to) != nil
            }
            guard !pool.isEmpty else { continue }
            let place = rng.pick(pool)
            let from = kind == .medevac ? place : anchor
            let to = kind == .medevac ? anchor : place
            guard let sizer = jobSizingPlane(kind: kind, from: from, to: to) else { continue }
            return dispatchLoad(kind: kind, from: from, to: to, seats: sizer.seats, hold: sizer.cargoKg)
        }
        return nil
    }

    /// The load and pay of a dispatch, sized to the aircraft that can fly it (no random draws).
    func dispatchLoad(kind: JobKind, from: Airport, to: Airport, seats: Int, hold: Int) -> DispatchPlan {
        var passengers = 0
        var cargo = 0
        switch kind {
        case .medevac: passengers = min(seats, 2)
        case .mail: cargo = min(hold, 250)
        case .fuelDrums: cargo = min(hold, 600)
        case .lodgeCharter: passengers = min(seats, 4); cargo = min(hold, 100)
        default: passengers = min(seats, 6)
        }
        let km = from.distanceKm(to: to)
        let fare = Fares.market(from: from, to: to, distanceKm: km)
        let base = Double(passengers) * fare + Double(cargo) * Fares.cargoRate(distanceKm: km) + 2.5 * km
        let pay = max(Tuning.dispatchMinPay(level: airline.level), Int((base * kind.payFactor * Tuning.dispatchPayBoost).rounded()))
        return DispatchPlan(kind: kind, from: from.code, to: to.code, passengers: passengers, cargoKg: cargo, pay: pay)
    }

    /// Today's dispatch on the board (offered or being flown), if any.
    public var dispatchToday: Job? {
        let today = ops.realDay
        return today > 0 ? ops.jobs.first { $0.dispatchDay == today } : nil
    }

    /// True once today's dispatch has earned its stamp.
    public var dispatchStampedToday: Bool { ops.dispatch.isStamped(ops.realDay) }

    /// Stamps still needed for the next reward (7 right after one).
    public var stampsToNextReward: Int { Tuning.stampsPerReward - ops.dispatch.stamps % Tuning.stampsPerReward }

    /// Puts the real day's dispatch on the board, once per real day. An old dispatch nobody took goes.
    mutating func postDailyDispatch() {
        let today = ops.realDay
        guard today > 0, ops.dispatch.postedDay != today, !ops.dispatch.isStamped(today) else { return }
        let kept = ops.jobs.filter { $0.dispatchDay == nil || $0.isTaken }
        ops.jobs = kept
        refreshJobArea()
        guard let plan = dispatchPlan(realDay: today) else { return }
        let id = ops.nextJobID
        ops.nextJobID += 1
        var job = Job(id: id, kind: plan.kind, from: plan.from, to: plan.to, passengers: plan.passengers, cargoKg: plan.cargoKg, pay: plan.pay,
                      deadlineMinute: clock.minute + Tuning.specialJobDeadlineMinutes, expiresMinute: clock.minute + Tuning.specialJobOpenMinutes,
                      aircraftID: nil, loaded: false)
        job.dispatchDay = today
        ops.jobs.append(job)
        ops.dispatch.postedDay = today
    }

    /// Keeps dispatch and seasonal jobs nobody has taken yet on the board while their real day or event lasts.
    mutating func keepSpecialJobsOpen() {
        let open = clock.minute + Tuning.specialJobOpenMinutes
        let deadline = clock.minute + Tuning.specialJobDeadlineMinutes
        for j in ops.jobs.indices where ops.jobs[j].isSpecial && !ops.jobs[j].isTaken {
            ops.jobs[j].expiresMinute = max(ops.jobs[j].expiresMinute, open)
            ops.jobs[j].deadlineMinute = max(ops.jobs[j].deadlineMinute, deadline)
        }
    }

    /// Game midnight: a dispatch or event job nobody has taken that no aircraft in the fleet can fly now (the fleet, a kit,
    /// the month or the slots changed) goes. Today's dispatch is then worked out again for the fleet as it is, and the event
    /// tops its jobs up again (RealDay.swift runs both after this).
    mutating func dropUnflyableSpecialJobs() {
        let jobs = ops.jobs
        let gone = jobs.filter { $0.isSpecial && !$0.isTaken && !jobCanBeFlown($0) }
        guard !gone.isEmpty else { return }
        let goneIDs = gone.map(\.id)
        ops.jobs = jobs.filter { !goneIDs.contains($0.id) }
        if gone.contains(where: { $0.dispatchDay == ops.realDay }) { ops.dispatch.postedDay = 0 }
    }

    /// Called when a job lands (JobFlights.landOnJob): stamps a dispatch, counts a seasonal job.
    mutating func noteSpecialJobDone(_ job: Job) {
        if let day = job.dispatchDay { earnStamp(day: day) }
        if let kind = job.season { countSeasonJob(kind) }
    }

    /// One stamp per real day at most, in any order (yesterday's dispatch landing after today's still counts). News subject
    /// "stamp:<total>", amount the stamps still needed for the next reward.
    mutating func earnStamp(day: Int) {
        guard day > 0, !ops.dispatch.isStamped(day) else { return }
        let days = (ops.dispatch.stampedDays + [day]).sorted()
        ops.dispatch.stampedDays = Array(days.suffix(Tuning.stampedDaysKept))
        ops.dispatch.lastStampDay = max(ops.dispatch.lastStampDay, day)
        ops.dispatch.stamps += 1
        addNews(.milestone, subject: "stamp:\(ops.dispatch.stamps)", amount: stampsToNextReward)
        if ops.dispatch.stamps % Tuning.stampsPerReward == 0 { giveStampReward() }
    }

    /// Every 7 stamps: the next classic livery (while any are left) and a rare find in the hangar (heritage and low-hours in turn).
    /// News subject "stampreward:<livery code or empty>", amount the rare find's listing id (0 if none fitted).
    mutating func giveStampReward() {
        ops.dispatch.rewardsEarned += 1
        let have = ops.unlockedLiveries
        let next = UnlockableLiveries.classicCodes.first { !have.contains($0) }
        if let next { unlockLivery(next) }
        let kind: RareFind = ops.dispatch.rewardsEarned % 2 == 1 ? .heritage : .lowHours
        let listing = addRareFind(kind)
        addNews(.milestone, subject: "stampreward:\(next ?? "")", amount: listing ?? 0)
    }
}
