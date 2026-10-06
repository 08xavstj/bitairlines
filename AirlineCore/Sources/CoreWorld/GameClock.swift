// CoreWorld/GameClock.swift: game time is a minute counter; the calendar is derived from it. The game starts on 2027-01-01 (a Friday).

public struct CalendarDate: Sendable, Hashable, Codable, Comparable {
    public var year: Int
    /// 1...12
    public var month: Int
    /// 1...31
    public var day: Int

    public static let epochYear = 2027

    public static func isLeap(_ year: Int) -> Bool { (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 }

    public static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The date `dayIndex` days after 2027-01-01.
    public init(dayIndex: Int) {
        var remaining = max(0, dayIndex)
        var y = CalendarDate.epochYear
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
        self.init(year: y, month: m, day: remaining + 1)
    }

    public static func < (a: CalendarDate, b: CalendarDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

public struct GameClock: Sendable, Hashable, Codable {
    public static let minutesPerDay = 1440

    /// Minutes since 2027-01-01 00:00.
    public var minute: Int

    public init(minute: Int = 0) { self.minute = minute }

    public var dayIndex: Int { minute / GameClock.minutesPerDay }
    public var minuteOfDay: Int { minute % GameClock.minutesPerDay }
    public var hour: Int { minuteOfDay / 60 }
    public var date: CalendarDate { CalendarDate(dayIndex: dayIndex) }
    /// 0 is Monday, 6 is Sunday. 2027-01-01 is a Friday.
    public var weekday: Int { (dayIndex + 4) % 7 }

    public static func minute(ofDay dayIndex: Int) -> Int { dayIndex * minutesPerDay }
}
