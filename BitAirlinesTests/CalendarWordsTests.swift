import Testing
import Foundation
import CoreCatalog
import CoreWorld
@testable import BitAirlines

/// The real-calendar features in the app: the real day passed to Core, and their words.
@Suite struct CalendarWordsTests {
    func check(_ text: String?, _ what: String) {
        let line = text ?? ""
        #expect(!line.isEmpty, "\(what) has no words")
        #expect(line.allSatisfy { $0.isASCII }, "\(what) uses a character the pixel font lacks")
        #expect(!line.contains("\u{2014}") && !line.contains("\u{2013}"), "\(what) has a dash")
    }

    @Test func theRealDayCountsLocalCalendarDaysFrom2000() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Pacific/Auckland"))
        let late = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 23, minute: 30)))
        #expect(RealDay.today(late, calendar: calendar) == 9775, "late in the evening is still the same local day")
        let first = try #require(calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: 8)))
        #expect(RealDay.today(first, calendar: calendar) == 0)
    }

    @Test func everySeasonAndSchemeHasPlainWords() {
        for kind in SeasonKind.allCases {
            check(CalendarWords.name(kind), "season \(kind)")
            check(CalendarWords.explain(kind), "season \(kind)")
        }
        for code in UnlockableLiveries.allCodes { check(CalendarWords.liveryName(code), "livery \(code)") }
        #expect(CalendarWords.liveryName("My scheme") == nil)
        #expect(Words.liveryName(UnlockableLiveries.classicCodes[0]) == "Classic cheat line")
    }

    /// NewsItem has no public initialiser outside Core, so the test builds one the way a save would hold it.
    func item(_ subject: String, _ amount: Int) throws -> NewsItem {
        let json = "{\"minute\":0,\"kind\":\"milestone\",\"subject\":\"\(subject)\",\"amount\":\(amount)}"
        return try JSONDecoder().decode(NewsItem.self, from: Data(json.utf8))
    }

    @Test func theNewsLinesReadCleanly() throws {
        let items = [
            try item("stamp:3", 4),
            try item("stamp:7", 7),
            try item("stampreward:classic.sunset", 12),
            try item("stampreward:", 0),
            try item("season:harvestFreight", 21),
            try item("seasonlivery:holidayParcels", 0),
            try item("realgoal:freightKg:YUB", 12_000),
        ]
        for news in items { check(CalendarWords.news(news), news.subject) }
        let other = try item("goal:passengers", 1)
        #expect(CalendarWords.news(other) == nil, "other milestones are left alone")
    }
}
