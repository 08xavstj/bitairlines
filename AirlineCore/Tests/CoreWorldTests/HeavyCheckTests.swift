import Foundation
import Testing
import CoreCatalog
@testable import CoreWorld

/// Heavy checks: they come due by the calendar or the hours, cost real money (even on credit), and an older save's fleet
/// does not all go in at once.
@Suite struct HeavyCheckTests {
    /// A Caravan on its route, waiting at the gate, its last heavy check more than four years ago, with no weather about.
    static func dueWorld() throws -> World {
        var w = try Fixtures.flyingWorld()
        w.market.closures = []
        let longAgo = w.clock.minute - (Tuning.heavyCheckIntervalDays + 1) * GameClock.minutesPerDay
        let flown = w.aircraft[0].totalBlockMinutes
        w.aircraft[0].heavyCheckMinuteStore = longAgo
        w.aircraft[0].heavyCheckBlockMinutesStore = flown
        w.aircraft[0].status = .boarding(until: w.clock.minute)
        return w
    }

    @Test func aHeavyCheckComesDueAndCostsMoney() throws {
        var w = try Self.dueWorld()
        let plane = w.aircraft[0]
        let due = w.isHeavyCheckDue(plane)
        let wait = w.daysUntilHeavyCheck(plane)
        let cost = w.heavyCheckCost(plane)
        let days = w.heavyCheckDays(plane)
        #expect(due)
        #expect(wait == 0)
        #expect(cost > 50_000, "a real bill, not a free check")
        #expect(days >= 5 && days <= Tuning.heavyCheckMaxDays)
        let cash = w.airline.cash
        let invested = w.today.investments
        let start = w.clock.minute

        w.depart(0)

        let after = w.aircraft[0]
        let until = start + days * GameClock.minutesPerDay
        #expect(w.airline.cash == cash - cost)
        #expect(w.today.investments == invested + cost)
        #expect(after.status == .maintenance(until: until))
        #expect(after.lastHeavyCheckMinute == until)
        #expect(after.condition >= Tuning.conditionAfterHeavyCheck)
        let dueAgain = w.isHeavyCheckDue(after)
        let nextWait = w.daysUntilHeavyCheck(after)
        #expect(!dueAgain)
        #expect(nextWait > 1000)
    }

    @Test func anOlderAircraftPaysMore() throws {
        let w = try Fixtures.world()
        var young = w.aircraft[0]
        young.builtDay = w.clock.dayIndex - 2 * 365
        var old = w.aircraft[0]
        old.builtDay = w.clock.dayIndex - 40 * 365
        let youngCost = w.heavyCheckCost(young)
        let oldCost = w.heavyCheckCost(old)
        #expect(oldCost > youngCost)
    }

    @Test func theHoursAloneCanMakeItDue() throws {
        var w = try Fixtures.world()
        let now = w.clock.minute
        w.aircraft[0].heavyCheckMinuteStore = now
        w.aircraft[0].heavyCheckBlockMinutesStore = 0
        w.aircraft[0].totalBlockMinutes = Int(Tuning.heavyCheckIntervalHours) * 60 + 60
        let plane = w.aircraft[0]
        let due = w.isHeavyCheckDue(plane)
        let wait = w.daysUntilHeavyCheck(plane)
        #expect(due)
        #expect(wait == 0)
    }

    @Test func withoutTheMoneyTheCheckStillHappensOnCredit() throws {
        var w = try Self.dueWorld()
        w.airline.cash = 1_000
        let cost = w.heavyCheckCost(w.aircraft[0])
        w.depart(0)
        #expect(w.airline.cash == 1_000 - cost)
        if case .maintenance = w.aircraft[0].status {} else { Testing.Issue.record("it goes in even without the money") }
    }

    @Test func noHeavyCheckInANewGamesFirstYear() throws {
        let w = try Fixtures.world()
        let wait = w.daysUntilHeavyCheck(w.aircraft[0])
        #expect(wait >= Tuning.heavyCheckFirstDueDays - w.clock.dayIndex)
    }

    @Test func aBoughtUsedAircraftIsNotDueForAYear() throws {
        var w = try Fixtures.world()
        w.airline.cash = 100_000_000
        w.clock.minute = 900 * GameClock.minutesPerDay
        w.market.listings.append(UsedListing(id: 9_999, typeID: "c208", ageYears: 30, condition: 70, price: 500_000, deliveryDays: 3))
        let planeID = try w.buyUsed(listingID: 9_999)
        let found = w.aircraft.first { $0.id == planeID }
        let plane = try #require(found)
        let wait = w.daysUntilHeavyCheck(plane)
        #expect(wait >= Tuning.heavyCheckFirstDueDays && wait < Tuning.heavyCheckIntervalDays)
    }

    @Test func anOldFleetFromAnOlderSaveDecodesAndDoesNotGoInAtOnce() throws {
        var w = try Fixtures.world()
        w.clock.minute = 2_000 * GameClock.minutesPerDay
        var template = w.aircraft[0]
        template.heavyCheckMinuteStore = nil
        template.heavyCheckBlockMinutesStore = nil
        template.restoration = nil

        // An aircraft from an older save: the new fields are simply not in the JSON.
        let data = try JSONEncoder().encode(template)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("heavyCheck") && !json.contains("restoration"))
        let old = try JSONDecoder().decode(Aircraft.self, from: data)
        #expect(old.lastHeavyCheckMinute == nil && old.restoration == nil && !old.awaitingRestoration)

        // Twelve old aircraft with many hours, none with a heavy check on record.
        var fleet: [Aircraft] = []
        for n in 1...12 {
            var plane = old
            plane.id = n
            plane.builtDay = -40 * 365
            plane.totalBlockMinutes = 30_000 * 60
            fleet.append(plane)
        }
        w.aircraft = fleet
        for i in w.aircraft.indices { w.recordHeavyCheckBaseline(i) }

        var dueNow = 0
        var waits: [Int] = []
        for plane in w.aircraft {
            if w.isHeavyCheckDue(plane) { dueNow += 1 }
            waits.append(w.daysUntilHeavyCheck(plane))
        }
        let soon = waits.filter { $0 < 60 }.count
        let earliest = waits.min() ?? 0
        let latest = waits.max() ?? 0
        #expect(dueNow <= 1, "the fleet does not all go in at once")
        #expect(soon <= 2)
        #expect(Set(waits).count == waits.count, "each aircraft has its own due day")
        #expect(latest - earliest > 2 * 365, "spread over the years")
    }
}
