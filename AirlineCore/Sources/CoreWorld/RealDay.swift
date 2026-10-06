// CoreWorld/RealDay.swift: the player's real calendar. Core has no wall clock: the app passes the real date in as a plain number,
// `realDay` = days since 2000-01-01 in the player's local calendar (RealCalendar.realDay(year:month:day:) does the sum).
// It is stored in Operations, and every real-calendar system (the daily dispatch, the real-week goal, seasonal events) reads it
// from there, so the simulation stays a pure function of the saved world.

/// Real calendar sums. Day 0 is Saturday 2000-01-01.
public enum RealCalendar {
    public static let epochYear = 2000

    /// Days since 2000-01-01 for a date (years before 2000 count as day 0).
    public static func realDay(year: Int, month: Int, day: Int) -> Int {
        guard year >= epochYear else { return 0 }
        var total = 0
        var y = epochYear
        while y < year {
            total += CalendarDate.isLeap(y) ? 366 : 365
            y += 1
        }
        var m = 1
        while m < month {
            total += CalendarDate.daysIn(month: m, year: year)
            m += 1
        }
        return total + max(0, day - 1)
    }

    /// The date of a real day.
    public static func date(realDay: Int) -> CalendarDate {
        var remaining = max(0, realDay)
        var y = epochYear
        while true {
            let length = CalendarDate.isLeap(y) ? 366 : 365
            if remaining < length { break }
            remaining -= length
            y += 1
        }
        var m = 1
        while remaining >= CalendarDate.daysIn(month: m, year: y) {
            remaining -= CalendarDate.daysIn(month: m, year: y)
            m += 1
        }
        return CalendarDate(year: y, month: m, day: remaining + 1)
    }

    /// 0 is Monday, 6 is Sunday. 2000-01-01 was a Saturday.
    public static func weekday(realDay: Int) -> Int { (max(0, realDay) + 5) % 7 }

    /// The Monday-to-Sunday week a real day falls in (week 1 starts on Monday 2000-01-03).
    public static func week(realDay: Int) -> Int { (max(0, realDay) + 5) / 7 }

    /// The real day of the Monday that starts a week.
    public static func monday(ofWeek week: Int) -> Int { week * 7 - 5 }
}

extension World {
    /// Today's real day as the app last reported it (0 until it has).
    public var realDay: Int { ops.realDay }

    /// The app calls this with today's real day when a game opens, when the app comes back to the front, and every so often
    /// while it is open. A new day posts the day's dispatch, a new real week sets a new real-week goal, and seasonal events
    /// switch on and off. Calling it again with the same day only fills in what is missing.
    public mutating func setRealDay(_ day: Int) {
        guard day > 0 else { return }
        if ops.realDay != day { ops.realDay = day }
        refreshRealCalendar()
    }

    /// Brings the real-calendar systems up to date with the stored real day. Also runs at every game midnight (before the job
    /// board is cleared), so a dispatch that could not be placed yet is retried as the network grows.
    mutating func refreshRealCalendar() {
        guard ops.realDay > 0 else { return }
        refreshSeason()
        postDailyDispatch()
        startRealWeekGoalIfNeeded()
        keepSpecialJobsOpen()
    }

    /// The game-midnight part (OperationsDaily.swift): the refresh above, and the running event's jobs topped up.
    mutating func dailyRealCalendar() {
        guard ops.realDay > 0 else { return }
        refreshRealCalendar()
        topUpSeasonJobs()
    }
}
