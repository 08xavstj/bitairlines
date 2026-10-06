// CoreWorld/SeasonalEvents.swift: a calendar of events on the real date (no server), the same for every player worldwide.
// Each lasts one to three weeks, lifts demand (everywhere, or to leisure airports: the coast, islands and seaplane bases),
// keeps a couple of event jobs on the board, and gives the event's own livery for 3 event jobs flown while it runs.
// The real date comes from the app (RealDay.swift). Event jobs are drawn from ops.rng like other board jobs.
import CoreCatalog
import CoreSim

public enum SeasonKind: String, Sendable, Hashable, Codable, CaseIterable {
    /// Around the Lunar New Year (late January or February): families travel home.
    case newYearRush
    /// The second half of March: school holidays and spring breaks.
    case springBreak
    /// Most of July: the summer holiday peak at the coast and on islands.
    case summerPeak
    /// Late September to mid October: harvest freight.
    case harvestFreight
    /// Late October to early November: festivals and visits home.
    case festivalSeason
    /// December before the holidays: parcels and mail.
    case holidayParcels
}

/// When an event runs, in real days (both ends included).
public struct SeasonWindow: Sendable, Hashable {
    public var kind: SeasonKind
    public var startDay: Int
    public var endDay: Int

    public func contains(_ day: Int) -> Bool { day >= startDay && day <= endDay }
    /// Days left including `day` itself (1 on the last day).
    public func daysLeft(from day: Int) -> Int { max(0, endDay - day + 1) }
}

/// The event running now, and how many of its jobs have been flown. Stored in Operations; older saves start empty.
public struct SeasonBook: Sendable, Hashable, Codable {
    public var active: SeasonKind?
    /// The real days the active event runs (0 when none).
    public var startDay = 0
    public var endDay = 0
    /// Event jobs flown during the active event.
    public var jobsDone = 0
    /// The last event that ended and its jobs flown, so a job taken while it ran still counts when it lands after the end.
    /// Missing from older saves.
    public var ended: SeasonKind?
    public var endedJobsDone = 0

    public init() {}

    enum CodingKeys: String, CodingKey { case active, startDay, endDay, jobsDone, ended, endedJobsDone }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = try c.decodeIfPresent(SeasonKind.self, forKey: .active)
        startDay = try c.decodeIfPresent(Int.self, forKey: .startDay) ?? 0
        endDay = try c.decodeIfPresent(Int.self, forKey: .endDay) ?? 0
        jobsDone = try c.decodeIfPresent(Int.self, forKey: .jobsDone) ?? 0
        ended = try c.decodeIfPresent(SeasonKind.self, forKey: .ended)
        endedJobsDone = try c.decodeIfPresent(Int.self, forKey: .endedJobsDone) ?? 0
    }
}

/// Which airports an event lifts.
public enum SeasonReach: Sendable, Hashable {
    case everywhere
    /// Airports by the sea (on the coast or an island) and seaplane bases.
    case leisure
}

/// What an event does to demand.
public struct SeasonLift: Sendable, Hashable {
    public var passengers: Double
    public var cargo: Double
    public var reach: SeasonReach
}

// MARK: Seasonal events
extension Tuning {
    /// Event jobs kept open on the board while an event runs.
    static let seasonJobsOpen = 2
    /// Event jobs pay this much more than ordinary board jobs.
    static let seasonJobPayBoost = 1.2
    /// Event jobs to fly for the event's livery.
    public static let seasonJobsForLivery = 3
    /// Tries at making a flyable event job each time the board is topped up.
    static let seasonJobTries = 8

    public static func seasonLift(_ kind: SeasonKind) -> SeasonLift {
        switch kind {
        case .newYearRush: SeasonLift(passengers: 1.25, cargo: 1.0, reach: .everywhere)
        case .springBreak: SeasonLift(passengers: 1.25, cargo: 1.0, reach: .leisure)
        case .summerPeak: SeasonLift(passengers: 1.35, cargo: 1.0, reach: .leisure)
        case .harvestFreight: SeasonLift(passengers: 1.0, cargo: 1.4, reach: .everywhere)
        case .festivalSeason: SeasonLift(passengers: 1.15, cargo: 1.1, reach: .everywhere)
        case .holidayParcels: SeasonLift(passengers: 1.0, cargo: 1.5, reach: .everywhere)
        }
    }

    /// The job kinds an event puts on the board.
    static func seasonJobKinds(_ kind: SeasonKind) -> [JobKind] {
        switch kind {
        case .newYearRush: return [JobKind.crewChange, JobKind.mail]
        case .springBreak: return [JobKind.lodgeCharter, JobKind.crewChange]
        case .summerPeak: return [JobKind.lodgeCharter, JobKind.crewChange]
        case .harvestFreight: return [JobKind.freight, JobKind.fuelDrums]
        case .festivalSeason: return [JobKind.crewChange, JobKind.lodgeCharter]
        case .holidayParcels: return [JobKind.mail, JobKind.freight]
        }
    }
}

public enum SeasonalEvents {
    /// Lunar New Year's day by year, as month * 100 + day (210 is 10 February). Years outside the table use 1 February.
    static let lunarNewYear: [Int: Int] = [
        2024: 210, 2025: 129, 2026: 217, 2027: 206, 2028: 126, 2029: 213, 2030: 203, 2031: 123,
        2032: 211, 2033: 131, 2034: 219, 2035: 208, 2036: 128, 2037: 215, 2038: 204, 2039: 124, 2040: 212,
    ]

    /// When an event runs in a year.
    public static func window(_ kind: SeasonKind, year: Int) -> SeasonWindow {
        func span(_ m1: Int, _ d1: Int, _ m2: Int, _ d2: Int) -> SeasonWindow {
            SeasonWindow(kind: kind, startDay: RealCalendar.realDay(year: year, month: m1, day: d1),
                         endDay: RealCalendar.realDay(year: year, month: m2, day: d2))
        }
        switch kind {
        case .newYearRush:
            let date = lunarNewYear[year] ?? 201
            let centre = RealCalendar.realDay(year: year, month: date / 100, day: date % 100)
            return SeasonWindow(kind: kind, startDay: centre - 7, endDay: centre + 7)
        case .springBreak: return span(3, 15, 3, 31)
        case .summerPeak: return span(7, 11, 7, 31)
        case .harvestFreight: return span(9, 22, 10, 12)
        case .festivalSeason: return span(10, 28, 11, 10)
        case .holidayParcels: return span(12, 4, 12, 23)
        }
    }

    /// The event running on a real day, if any (the windows never overlap).
    public static func active(onRealDay day: Int) -> SeasonWindow? {
        let year = RealCalendar.date(realDay: day).year
        for kind in SeasonKind.allCases {
            let w = window(kind, year: year)
            if w.contains(day) { return w }
        }
        return nil
    }

    /// The next event to start after a real day.
    public static func next(afterRealDay day: Int) -> SeasonWindow {
        let year = RealCalendar.date(realDay: day).year
        var best = window(.newYearRush, year: year + 1)
        for y in [year, year + 1] {
            for kind in SeasonKind.allCases {
                let w = window(kind, year: y)
                if w.startDay > day && w.startDay < best.startDay { best = w }
            }
        }
        return best
    }

    /// An airport by the sea (some point about 20 km away is water) or a seaplane base.
    public static func isLeisure(_ airport: Airport) -> Bool {
        if airport.kind == .seaplane { return true }
        let step = 0.2
        let mask = LandMask.world
        return !mask.isLand(latitude: airport.latitude + step, longitude: airport.longitude)
            || !mask.isLand(latitude: airport.latitude - step, longitude: airport.longitude)
            || !mask.isLand(latitude: airport.latitude, longitude: airport.longitude + step)
            || !mask.isLand(latitude: airport.latitude, longitude: airport.longitude - step)
    }
}

extension World {
    /// The event running now (as of the last real day the app passed in), with its dates.
    public var activeSeason: SeasonWindow? {
        guard let kind = ops.season.active else { return nil }
        return SeasonWindow(kind: kind, startDay: ops.season.startDay, endDay: ops.season.endDay)
    }

    /// How much the running event lifts demand on a leg (1 and 1 when none). Used with eventFactors in Events.swift.
    func seasonFactors(from a: Airport, to b: Airport) -> (passengers: Double, cargo: Double) {
        guard let kind = ops.season.active else { return (1, 1) }
        let lift = Tuning.seasonLift(kind)
        switch lift.reach {
        case .everywhere:
            return (lift.passengers, lift.cargo)
        case .leisure:
            let toLeisure = SeasonalEvents.isLeisure(b)
            return (toLeisure || SeasonalEvents.isLeisure(a) ? lift.passengers : 1, toLeisure ? lift.cargo : 1)
        }
    }

    /// Switches events on and off by the stored real day. When one ends its untaken jobs go (the ones being flown still count
    /// when they land); when one starts it says so in the news (subject "season:<kind>", amount the days it runs) and puts its
    /// first jobs on the board.
    mutating func refreshSeason() {
        let window = SeasonalEvents.active(onRealDay: ops.realDay)
        guard window?.kind != ops.season.active || (window?.startDay ?? 0) != ops.season.startDay else { return }
        let kept = ops.jobs.filter { $0.season == nil || $0.isTaken }
        ops.jobs = kept
        let before = ops.season
        ops.season = SeasonBook()
        if let kind = before.active {
            ops.season.ended = kind
            ops.season.endedJobsDone = before.jobsDone
        } else {
            ops.season.ended = before.ended
            ops.season.endedJobsDone = before.endedJobsDone
        }
        guard let window else { return }
        ops.season.active = window.kind
        ops.season.startDay = window.startDay
        ops.season.endDay = window.endDay
        addNews(.milestone, subject: "season:\(window.kind.rawValue)", amount: window.daysLeft(from: ops.realDay))
        topUpSeasonJobs()
    }

    /// Keeps `Tuning.seasonJobsOpen` event jobs on offer while an event runs. Run when it starts and at every game midnight.
    /// Event jobs never expire by game time, so only jobs some aircraft in the fleet can fly this month go on the board
    /// (an unflyable one would sit in its slot until the event ends).
    mutating func topUpSeasonJobs() {
        guard let kind = ops.season.active else { return }
        refreshJobArea()
        let kinds = Tuning.seasonJobKinds(kind)
        var tries = 0
        while ops.jobs.filter({ $0.season == kind && !$0.isTaken }).count < Tuning.seasonJobsOpen && tries < Tuning.seasonJobTries {
            tries += 1
            let jobKind = ops.rng.pick(kinds)
            guard var job = makeJob(kind: jobKind), jobCanBeFlown(job) else { continue }
            job.season = kind
            job.pay = Int((Double(job.pay) * Tuning.seasonJobPayBoost).rounded())
            ops.jobs.append(job)
        }
        keepSpecialJobsOpen()
    }

    /// An event job landed. The third earns the event's livery (news subject "seasonlivery:<kind>"). A job taken while the
    /// event ran counts for it even when it lands after the end.
    mutating func countSeasonJob(_ kind: SeasonKind) {
        let done: Int
        if ops.season.active == kind {
            ops.season.jobsDone += 1
            done = ops.season.jobsDone
        } else if ops.season.ended == kind {
            ops.season.endedJobsDone += 1
            done = ops.season.endedJobsDone
        } else {
            return
        }
        if done >= Tuning.seasonJobsForLivery, unlockLivery(UnlockableLiveries.seasonCode(kind)) {
            addNews(.milestone, subject: "seasonlivery:\(kind.rawValue)", amount: 0)
        }
    }
}
