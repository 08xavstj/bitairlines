import Testing
import Foundation
import CoreWorld
@testable import BitAirlines

/// The real day the app passes to Core is counted on the Gregorian calendar whatever calendar the phone is set to; only the
/// time zone comes from the phone, so the day turns at local midnight. Also the words for the job news lines.
@Suite struct RealDayCalendarTests {
    /// NewsItem has no public initialiser outside Core, so the test builds one the way a save would hold it.
    func item(_ subject: String, _ amount: Int) throws -> NewsItem {
        let json = "{\"minute\":0,\"kind\":\"milestone\",\"subject\":\"\(subject)\",\"amount\":\(amount)}"
        return try JSONDecoder().decode(NewsItem.self, from: Data(json.utf8))
    }

    @Test func theJobNewsLinesReadCleanly() throws {
        let medevac = try item("medevac:YEV:YUB", 9_500)
        var items = [medevac]
        for reason in JobGiveUpReason.allCases {
            let gone = try item("jobgone:C-FABC:YUB", reason.rawValue)
            items.append(gone)
        }
        for news in items {
            let line = CalendarWords.news(news) ?? ""
            #expect(!line.isEmpty, "\(news.subject) \(news.amount) has no words")
            #expect(line.allSatisfy { $0.isASCII }, "\(news.subject) uses a character the pixel font lacks")
            #expect(!line.contains("!"), "\(news.subject) shouts")
        }
        let line = CalendarWords.news(medevac) ?? ""
        #expect(line.contains("Medevac") && line.contains("Inuvik"))
    }

    @Test func everyPhoneCalendarGivesTheSameRealDay() throws {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = try #require(TimeZone(identifier: "Asia/Tehran"))
        let noon = try #require(gregorian.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 12)))
        let expected = RealDay.today(noon, calendar: gregorian)
        #expect(expected == 9775)
        let others: [Calendar.Identifier] = [.japanese, .persian, .buddhist, .islamicUmmAlQura, .republicOfChina, .hebrew, .indian, .coptic]
        for identifier in others {
            var calendar = Calendar(identifier: identifier)
            calendar.timeZone = gregorian.timeZone
            #expect(RealDay.today(noon, calendar: calendar) == expected, "\(identifier)")
        }
    }

    @Test func theDayTurnsAtLocalMidnightInThePhonesTimeZone() throws {
        var tokyo = Calendar(identifier: .japanese)
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        // 23:30 UTC on 6 October is already 7 October in Tokyo.
        let late = try #require(utc.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 23, minute: 30)))
        #expect(RealDay.today(late, calendar: utc) == 9775)
        #expect(RealDay.today(late, calendar: tokyo) == 9776)
    }
}
