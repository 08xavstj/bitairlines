// CoreWorld/HeavyChecks.swift: heavy checks. Every few years, or after so many block hours, an aircraft spends weeks in the
// hangar and the airline pays a real bill that grows with the type's price and age, so keeping an old aircraft is a decision.
// The scheduled check when worn (below the maintenance threshold) stays free and quick.
// Older saves and new games have no heavy check on record: their due days are spread over the years by aircraft id, so a
// fleet never goes in all at once. No random draws here.
import CoreCatalog

// MARK: Heavy checks
extension Tuning {
    /// Calendar days between heavy checks (four years)...
    public static let heavyCheckIntervalDays = 1461
    /// ...or block hours between heavy checks, whichever comes first.
    public static let heavyCheckIntervalHours = 6000.0
    /// Days in the hangar: the base plus a day for every few years of age, up to the most. Halved with a hangar or the mechanics' perk.
    public static let heavyCheckBaseDays = 10
    public static let heavyCheckMaxDays = 20
    public static let heavyCheckYearsPerExtraDay = 3.0
    /// The bill: this share of the type's new price, times 1 + the age term per year of age (capped).
    public static let heavyCheckPriceShare = 0.03
    public static let heavyCheckAgeCostPerYear = 0.03
    public static let heavyCheckAgeCostCap = 2.5
    /// Condition after a heavy check.
    public static let conditionAfterHeavyCheck = 99.0
    /// The odds of a breakdown rise by this share for every year since the last heavy check, up to the cap.
    public static let heavyCheckWearPerYear = 0.05
    public static let heavyCheckWearCap = 1.5
    /// An aircraft with no heavy check on record is first due at least this many days into the game (or after it was bought)...
    public static let heavyCheckFirstDueDays = 365
    /// ...and aircraft with consecutive ids are this many days apart (spread over the rest of the interval).
    public static let heavyCheckSpreadStride = 397
}

extension Aircraft {
    /// The minute its last heavy check ended (or will end, while it is in), if one is on record.
    public var lastHeavyCheckMinute: Int? { heavyCheckMinuteStore }
}

extension World {
    /// Days from a fixed start until an aircraft with this id is first due: between `heavyCheckFirstDueDays` and the interval.
    static func heavyCheckSpreadDays(id: Int) -> Int {
        let window = Tuning.heavyCheckIntervalDays - Tuning.heavyCheckFirstDueDays
        let k = (id * Tuning.heavyCheckSpreadStride) % window
        return Tuning.heavyCheckFirstDueDays + (k < 0 ? k + window : k)
    }

    /// Integer division rounding down, also for negative numbers.
    static func floorDivide(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }

    /// The day the aircraft's last heavy check ended. With none on record: the latest day on its own four-year cycle (the
    /// cycles start a spread number of days into the game), and never before it was built.
    public func lastHeavyCheckDay(_ plane: Aircraft) -> Int {
        if let minute = plane.heavyCheckMinuteStore { return World.floorDivide(minute, GameClock.minutesPerDay) }
        let interval = Tuning.heavyCheckIntervalDays
        let phase = World.heavyCheckSpreadDays(id: plane.id)
        let cycle = phase + World.floorDivide(clock.dayIndex - phase, interval) * interval
        return max(cycle, plane.builtDay)
    }

    /// Block hours flown since the last heavy check began (with none on record, counted from now).
    public func blockHoursSinceHeavyCheck(_ plane: Aircraft) -> Double {
        let base = plane.heavyCheckBlockMinutesStore ?? plane.totalBlockMinutes
        return Double(plane.totalBlockMinutes - base) / 60.0
    }

    /// True when the calendar or the block hours say the heavy check is due.
    public func isHeavyCheckDue(_ plane: Aircraft) -> Bool {
        if clock.dayIndex >= lastHeavyCheckDay(plane) + Tuning.heavyCheckIntervalDays { return true }
        return blockHoursSinceHeavyCheck(plane) >= Tuning.heavyCheckIntervalHours
    }

    /// Days until the next heavy check: by the calendar, or sooner by the hours at the pace flown since the last one. 0 when due.
    public func daysUntilHeavyCheck(_ plane: Aircraft) -> Int {
        if isHeavyCheckDue(plane) { return 0 }
        let last = lastHeavyCheckDay(plane)
        var days = last + Tuning.heavyCheckIntervalDays - clock.dayIndex
        let hours = blockHoursSinceHeavyCheck(plane)
        let since = clock.dayIndex - last
        if hours > 0 && since > 0 {
            let hoursPerDay = hours / Double(since)
            let byHours = (Tuning.heavyCheckIntervalHours - hours) / hoursPerDay
            days = min(days, Int(byHours))
        }
        return max(0, days)
    }

    /// What a heavy check costs today: a share of the type's new price that grows with the aircraft's age.
    public func heavyCheckCost(_ plane: Aircraft) -> Int {
        guard let type = plane.type else { return 0 }
        let age = max(0, plane.ageYears(atDay: clock.dayIndex))
        let ageFactor = min(Tuning.heavyCheckAgeCostCap, 1.0 + Tuning.heavyCheckAgeCostPerYear * age)
        return Int((Double(type.priceUSD) * Tuning.heavyCheckPriceShare * ageFactor * maintenanceFactor).rounded())
    }

    /// Days in the hangar for a heavy check, halved where the airline has a hangar or the mechanics' perk.
    public func heavyCheckDays(_ plane: Aircraft) -> Int {
        let age = max(0, plane.ageYears(atDay: clock.dayIndex))
        var days = min(Tuning.heavyCheckMaxDays, Tuning.heavyCheckBaseDays + Int(age / Tuning.heavyCheckYearsPerExtraDay))
        if hasHangar(at: plane.location) || has(.mechanicsGuild) { days = max(1, days / 2) }
        return days
    }

    /// Breakdown odds multiplier from the years since the last heavy check: 1 just after one, rising slowly. A heavy check resets it.
    public func heavyCheckWear(_ plane: Aircraft) -> Double {
        let years = Double(max(0, clock.dayIndex - lastHeavyCheckDay(plane))) / 365.25
        return min(Tuning.heavyCheckWearCap, 1.0 + Tuning.heavyCheckWearPerYear * years)
    }

    /// Puts a heavy check on record for an aircraft that has none (an older save or a new game), so its due day stays put.
    mutating func recordHeavyCheckBaseline(_ i: Int) {
        if aircraft[i].heavyCheckMinuteStore == nil {
            let day = lastHeavyCheckDay(aircraft[i])
            aircraft[i].heavyCheckMinuteStore = day * GameClock.minutesPerDay
        }
        if aircraft[i].heavyCheckBlockMinutesStore == nil {
            let flown = aircraft[i].totalBlockMinutes
            aircraft[i].heavyCheckBlockMinutesStore = flown
        }
    }

    /// Records a heavy check that ends at `until` (also used by a restoration, which includes one).
    mutating func markHeavyCheck(_ i: Int, until: Int) {
        let flown = aircraft[i].totalBlockMinutes
        aircraft[i].heavyCheckMinuteStore = until
        aircraft[i].heavyCheckBlockMinutesStore = flown
    }

    /// Sends the aircraft in for its heavy check if one is due. The bill is paid even into the overdraft: the check is not
    /// optional, and the overdraft rules take it from there. True if it went in.
    mutating func startHeavyCheckIfDue(_ i: Int) -> Bool {
        recordHeavyCheckBaseline(i)
        guard isHeavyCheckDue(aircraft[i]) else { return false }
        let cost = heavyCheckCost(aircraft[i])
        let until = clock.minute + heavyCheckDays(aircraft[i]) * GameClock.minutesPerDay
        spendOnInvestment(cost)
        let condition = max(aircraft[i].condition, Tuning.conditionAfterHeavyCheck)
        aircraft[i].condition = condition
        markHeavyCheck(i, until: until)
        aircraft[i].status = .maintenance(until: until)
        return true
    }

    /// The scheduled check when worn: free, a few days, quicker at a base with a hangar. True if it went in.
    /// Used by depart() and by job flights.
    mutating func startCheckIfWorn(_ i: Int) -> Bool {
        guard aircraft[i].condition < Tuning.maintenanceThreshold else { return false }
        var days = max(1, Int((Tuning.conditionAfterCheck - aircraft[i].condition) / 10.0))
        if hasHangar(at: aircraft[i].location) || has(.mechanicsGuild) { days = max(1, days / 2) }
        aircraft[i].status = .maintenance(until: clock.minute + days * GameClock.minutesPerDay)
        return true
    }
}
