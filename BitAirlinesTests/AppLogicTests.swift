import Testing
import Foundation
import CoreCatalog
import CoreWorld
@testable import BitAirlines

@Suite struct FormatTests {
    @Test func numbersAndMoney() {
        #expect(Format.number(1234567) == "1,234,567")
        #expect(Format.number(-1200) == "-1,200")
        #expect(Format.dollars(2500000) == "$2,500,000")
        #expect(Format.dollars(-45) == "-$45")
        #expect(Format.compactMoney(1_250_000) == "$1.2M" || Format.compactMoney(1_250_000) == "$1.3M")
        #expect(Format.compactMoney(450_000) == "$450k")
        #expect(Format.compactMoney(8_500) == "$8,500")
        #expect(Format.signedMoney(-300_000) == "-$300k")
    }

    @Test func forecastFigures() {
        #expect(Format.perDay(1246.4) == "+$1,246 a day")
        #expect(Format.perDay(-22) == "-$22 a day")
        #expect(Format.payback(years: 0.04) == "1 month")
        #expect(Format.payback(years: 0.5) == "6 months")
        #expect(Format.payback(years: 3.24) == "3.2 years")
        #expect(Format.payback(years: 14) == "over 10 years")
        #expect(Format.payback(years: nil) == "never")
    }

    @Test func datesAndTimes() {
        #expect(Format.date(CalendarDate(year: 2027, month: 1, day: 5)) == "Jan 5, 2027")
        #expect(Format.time(GameClock(minute: 6 * 60 + 5)) == "06:05")
        #expect(Format.duration(minutes: 125) == "2h 05m")
        #expect(Format.duration(minutes: 40) == "40m")
    }
}

@Suite struct MessageTests {
    @Test func everyRefusalHasWords() {
        let errors: [WorldError] = [
            .unknownAirport("X"), .unknownType("x"), .unknownAircraft(1), .unknownRoute(1), .unknownListing(1), .unknownIssue(1), .notEnoughCash(needed: 5),
            .levelTooLow(required: 3), .airportLevelTooHigh(airport: "YEG", required: 4), .permitRequired(country: "US", price: 1), .routeNeedsTwoStops, .tooManyStops,
            .duplicateStops, .aircraftCannotUse(airport: "YEV"), .outOfRange(km: 5), .notDelivered, .aircraftBusy, .aircraftHasRoute, .notInProduction, .invalidChoice,
            .requirementsNotMet, .alreadyHasPermit, .invalidAmount, .fuelStorageFull(capacityKg: 20_000), .noFuel(airport: "YUB"), .alreadyBuilt,
            .cannotBuildHere, .kitDoesNotFit, .jobUnavailable, .notEnoughRoom,
        ]
        for e in errors {
            let text = Messages.describe(e)
            #expect(!text.isEmpty && text.allSatisfy { $0.isASCII }, "\(e)")
            #expect(!text.contains("\u{2014}"), "no em dashes in player text")
        }
    }

    @Test func issuesAndNewsReadCleanly() throws {
        var w = try World.newGame(NewGameConfig(airlineName: "Test Air", airlineCode: "TA", homeAirport: "YEV", branding: .starter, difficulty: .standard, starterTypeID: "c208", seed: 5))
        let route = try w.createRoute(stops: ["YEV", "YUB"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        w.advance(byMinutes: 5 * 1440)
        for item in w.news { #expect(!Messages.news(item, in: w).isEmpty) }
        for choice in [IssueChoice.repairNow, .flyInMechanic, .waitForParts, .emergencyLoan, .declareBankruptcy, .acknowledge] { #expect(!Messages.name(choice).isEmpty) }
    }
}

@Suite struct SaveStoreTests {
    func tempStore() -> SaveStore {
        SaveStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("bitairlines-test-\(UUID().uuidString)"))
    }

    @Test func aSaveRoundTrips() throws {
        let store = tempStore()
        var w = try World.newGame(NewGameConfig(airlineName: "Round Trip Air", airlineCode: "RT", homeAirport: "BET", branding: .starter, difficulty: .easy, starterTypeID: "c208", seed: 9))
        let route = try w.createRoute(stops: ["BET", "OTZ"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        w.advance(byMinutes: 3 * 1440)
        try store.save(w, slot: 2)
        #expect(FileManager.default.fileExists(atPath: store.summaryURL(slot: 2).path), "a small summary file sits next to the save")
        let back = try store.load(slot: 2)
        #expect(back.airline.cash == w.airline.cash && back.clock == w.clock && back.aircraft == w.aircraft && back.routes == w.routes)
        let summary = try #require(store.summary(slot: 2))
        #expect(summary.airlineName == "Round Trip Air" && summary.aircraft == 1)
        #expect(store.freeSlot() == 1)
        store.delete(slot: 2)
        #expect(store.summary(slot: 2) == nil)
    }

    @Test func aMissingOrBrokenSaveIsHandled() throws {
        let store = tempStore()
        #expect(store.summary(slot: 1) == nil)
        #expect(throws: (any Error).self) { try store.load(slot: 1) }
        try Data("not json".utf8).write(to: store.url(slot: 1))
        #expect(store.summary(slot: 1)?.broken == true, "a save that cannot be read is listed, not hidden")
        #expect(store.freeSlot() == 2, "and its slot is not handed to a new game")
    }
}

@MainActor @Suite struct SessionTests {
    @Test func refusalsBecomeNotices() throws {
        let w = try World.newGame(NewGameConfig(airlineName: "Notice Air", airlineCode: "NA", homeAirport: "YEV", branding: .starter, difficulty: .standard, starterTypeID: "c208", seed: 3))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bitairlines-test-\(UUID().uuidString)")
        let session = GameSession(world: w, slot: 1, store: SaveStore(directory: dir))
        #expect(session.perform { _ = try $0.createRoute(stops: ["YEV", "YEG"]) } == false)
        #expect(session.notice?.contains("Edmonton") == true)
        #expect(session.perform { _ = try $0.createRoute(stops: ["YEV", "YUB"]) } == true)
        #expect(session.notice == nil && session.world.routes.count == 1)
    }

    @Test func speedsAreOrdered() {
        let rates = GameSpeed.allCases.map(\.minutesPerSecond)
        #expect(rates == rates.sorted() && rates.first == 0)
    }
}
