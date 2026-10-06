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

    /// 125 minutes -> "2h 05m"
    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return "\(h)h " + (m < 10 ? "0" : "") + "\(m)m"
    }
}
