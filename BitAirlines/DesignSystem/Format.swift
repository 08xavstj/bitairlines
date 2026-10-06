import Foundation
import CoreWorld

/// Turns numbers from the game core into the words and figures the screens show. ASCII only (the pixel font has no accents).
enum Format {
    /// 1234567 -> "1,234,567"
    static func number(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }

    static func dollars(_ amount: Int) -> String { (amount < 0 ? "-$" : "$") + number(abs(amount)).replacingOccurrences(of: "-", with: "") }

    /// $1.2M, $450k, $85: for tight spaces.
    static func compactMoney(_ amount: Int) -> String {
        let a = abs(amount)
        let sign = amount < 0 ? "-" : ""
        if a >= 1_000_000_000 { return sign + "$" + oneDecimal(Double(a) / 1_000_000_000) + "B" }
        if a >= 1_000_000 { return sign + "$" + oneDecimal(Double(a) / 1_000_000) + "M" }
        if a >= 10_000 { return sign + "$" + String(a / 1000) + "k" }
        return dollars(amount)
    }

    static func signedMoney(_ amount: Int) -> String { (amount >= 0 ? "+" : "") + compactMoney(amount) }

    static func oneDecimal(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        return "\(tenths / 10).\(abs(tenths % 10))"
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    /// A forecast daily result: "+$1,246 a day".
    static func perDay(_ amount: Double) -> String { signedMoney(Int(amount.rounded())) + " a day" }

    /// How long a purchase takes to earn itself back: "5 months", "3.2 years", "never".
    static func payback(years: Double?) -> String {
        guard let years, years.isFinite else { return "never" }
        if years < 1 {
            let months = max(1, Int((years * 12).rounded()))
            return months == 1 ? "1 month" : "\(months) months"
        }
        if years >= 10 { return "over 10 years" }
        return oneDecimal(years) + " years"
    }

    static func km(_ value: Double) -> String { number(Int(value.rounded())) + " km" }

    static func people(_ n: Int) -> String {
        if n >= 1_000_000 { return oneDecimal(Double(n) / 1_000_000) + "M" }
        if n >= 10_000 { return String(n / 1000) + "k" }
        return number(n)
    }

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    static func date(_ d: CalendarDate) -> String { "\(months[min(max(d.month, 1), 12) - 1]) \(d.day), \(d.year)" }

    static func time(_ clock: GameClock) -> String {
        let h = clock.hour, m = clock.minuteOfDay % 60
        return (h < 10 ? "0" : "") + "\(h):" + (m < 10 ? "0" : "") + "\(m)"
    }

    static let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// A time the player can place: "06:00" today, "Sat 06:00" later this week, "Feb 20, 2027 06:00" further out.
    static func when(_ clock: GameClock, now: GameClock) -> String {
        let days = clock.dayIndex - now.dayIndex
        if days == 0 { return time(clock) }
        if days > 0 && days < 7 { return "\(weekdays[clock.weekday]) \(time(clock))" }
        return "\(date(clock.date)) \(time(clock))"
    }

    /// 125 minutes -> "2h 05m"
    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return "\(h)h " + (m < 10 ? "0" : "") + "\(m)m"
    }

    /// A wait of hours or days: 300 -> "5h", 2160 -> "1 day 12h", 2880 -> "2 days"
    static func wait(minutes: Int) -> String {
        let hours = (minutes + 59) / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24, rest = hours % 24
        return "\(days) day" + (days == 1 ? "" : "s") + (rest > 0 ? " \(rest)h" : "")
    }
}
