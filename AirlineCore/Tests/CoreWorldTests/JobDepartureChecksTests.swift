import Testing
import CoreCatalog
@testable import CoreWorld

/// A job flight goes through the same departure checks as a route flight: frozen lakes this month, the check when worn,
/// the crew day.
@Suite struct JobDepartureChecksTests {
    /// Day index of 30 October 2027 and of 2 November 2027.
    static let october30 = 302
    static let november2 = 305

    /// A Caravan floatplane parked on a lake north of 60 degrees, on 30 October, with a job to another such lake nearby.
    /// Returns the world and the floatplane's index.
    static func lakeWorld() throws -> (World, Int) {
        var w = try Fixtures.world()
        w.setPausePolicy(.never)
        let lakes = AirportCatalog.all.filter { $0.surface == .water && $0.latitude > 60 }
        var pair: (Airport, Airport)?
        search: for a in lakes {
            for b in lakes where b.code != a.code && a.distanceKm(to: b) < 900 {
                pair = (a, b)
                break search
            }
        }
        let lakesFound = try #require(pair)
        let from = lakesFound.0
        let to = lakesFound.1
        w.clock.minute = october30 * GameClock.minutesPerDay + 10 * 60
        w.market.closures = []
        w.aircraft.append(Aircraft(id: 77, typeID: "c208f", registration: "C-FLAK", builtDay: 0, condition: 90, price: 3_000_000,
                                   location: from.code, status: .idle))
        w.ops.jobs.append(Job(id: 900, kind: .crewChange, from: from.code, to: to.code, passengers: 2, cargoKg: 0, pay: 5_000,
                              deadlineMinute: w.clock.minute + 5 * 1440, expiresMinute: w.clock.minute + 1440, aircraftID: nil, loaded: false))
        try w.takeJob(jobID: 900, aircraftID: 77)
        return (w, w.aircraft.count - 1)
    }

    static func loaded(_ w: World) -> Bool { w.ops.jobs.first { $0.id == 900 }?.loaded ?? false }

    @Test func aFloatplaneJobToAFrozenLakeWaitsForTheThaw() throws {
        let made = try Self.lakeWorld()
        var w = made.0
        let i = made.1
        #expect(w.aircraft[i].jobID == 900, "taken in October, when the lakes are open")

        // November: the lakes are ice. It must not take off.
        w.clock.minute = Self.november2 * GameClock.minutesPerDay + 10 * 60
        w.aircraft[i].status = .boarding(until: w.clock.minute)
        w.depart(i)
        let firstOfDecember = 334 * GameClock.minutesPerDay
        #expect(!Self.loaded(w))
        #expect(w.aircraft[i].flight == nil)
        if case .boarding(let until) = w.aircraft[i].status {
            #expect(until >= firstOfDecember)
        } else {
            Testing.Issue.record("it waits at the gate for the thaw")
        }
    }

    @Test func aWornAircraftOnAJobGoesForItsCheckFirst() throws {
        let made = try Self.lakeWorld()
        var w = made.0
        let i = made.1
        w.aircraft[i].condition = Tuning.maintenanceThreshold - 15
        w.aircraft[i].status = .boarding(until: w.clock.minute)
        w.depart(i)
        #expect(!Self.loaded(w))
        if case .maintenance = w.aircraft[i].status {} else { Testing.Issue.record("it goes for its check before loading") }
    }

    @Test func aJobWaitsWhenTheCrewDayIsUsedUp() throws {
        let made = try Self.lakeWorld()
        var w = made.0
        let i = made.1
        w.aircraft[i].blockMinutesToday = 9 * 60
        w.aircraft[i].status = .boarding(until: w.clock.minute)
        w.depart(i)
        let tomorrowMorning = (Self.october30 + 1) * GameClock.minutesPerDay + 6 * 60
        #expect(!Self.loaded(w))
        #expect(w.aircraft[i].status == .boarding(until: tomorrowMorning))
    }
}
