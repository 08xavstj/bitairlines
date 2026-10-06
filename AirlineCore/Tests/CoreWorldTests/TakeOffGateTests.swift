import Testing
import CoreCatalog
@testable import CoreWorld

/// Every take-off goes through one gate (Flights.swift), empty positioning hops too: weather, the season, the crew day, daylight,
/// slots and a pilot. An aircraft flying empty heads for the nearest stop it can use this month, and gives up (with a news item)
/// when it can never get there (Positioning.swift). At midnight the new day starts before the aircraft due at 00:00 move.
@Suite struct TakeOffGateTests {
    /// Day index of 15 June 2027.
    static let june15 = 165

    /// The starter Caravan parked at Inuvik, and a route that does not touch Inuvik, listed far stop first: Sachs Harbour
    /// (514 km) and Tuktoyaktuk (127 km). Relaxed mode, so no daylight limit or weather of its own. Not assigned yet.
    static func awayWorld() throws -> (World, Int) {
        var w = try Fixtures.world(mode: .easy)
        w.setPausePolicy(.never)
        w.market.closures = []
        let route = try w.createRoute(stops: ["YSY", "YUB"])
        return (w, route)
    }

    /// A Normal world on 15 June at noon, with a permit for the United States.
    static func juneWorld() throws -> World {
        var w = try Fixtures.world()
        w.setPausePolicy(.never)
        w.market.closures = []
        w.airline.permits.append("US")
        w.clock.minute = june15 * GameClock.minutesPerDay + 12 * 60
        return w
    }

    // MARK: Where an empty flight goes

    @Test func anAircraftAwayFromItsRouteFliesToTheNearestStop() throws {
        let made = try Self.awayWorld()
        var w = made.0
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: made.1)
        #expect(w.aircraft[0].flight?.isFerry == true)
        #expect(w.aircraft[0].flight?.to == "YUB", "Tuktoyaktuk is nearer than Sachs Harbour, which is listed first")
        #expect(w.aircraft[0].blockMinutesToday > 0, "an empty hop counts towards the crew day")
    }

    @Test func anEmptyHopGoesToAStopItCanUseThisMonth() throws {
        var w = try Self.juneWorld()
        #expect(CalendarDate(dayIndex: Self.june15) == CalendarDate(year: 2027, month: 6, day: 15))
        w.aircraft[0].location = "BET"
        w.aircraft[0].kits = [.wheelSkis]
        // Nunapitchuk is a lake 36 km from Bethel, Aniak a runway 152 km away. In June the lake is open water: no place for skis.
        let route = try w.createRoute(stops: ["NUP", "ANI"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        #expect(w.aircraft[0].flight?.isFerry == true)
        #expect(w.aircraft[0].flight?.to == "ANI")
    }

    // MARK: The gate

    @Test func anEmptyHopWaitsForTheWeather() throws {
        let made = try Self.awayWorld()
        var w = made.0
        let until = w.clock.minute + 2 * GameClock.minutesPerDay
        w.market.closures.append(Closure(airport: "YUB", untilMinute: until))
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: made.1)
        #expect(w.aircraft[0].flight == nil)
        #expect(w.aircraft[0].status == .boarding(until: until))
        w.advance(byMinutes: 3 * GameClock.minutesPerDay)
        let there = w.aircraft[0].location == "YUB" || w.aircraft[0].location == "YSY"
        #expect(there, "it goes once the weather clears")
    }

    @Test func anEmptyHopWaitsWhenTheCrewDayIsUsedUp() throws {
        let made = try Self.awayWorld()
        var w = made.0
        w.aircraft[0].blockMinutesToday = 9 * 60
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: made.1)
        let tomorrowMorning = (w.clock.dayIndex + 1) * GameClock.minutesPerDay + 6 * 60
        #expect(w.aircraft[0].flight == nil)
        #expect(w.aircraft[0].status == .boarding(until: tomorrowMorning))
    }

    @Test func anEmptyHopNeedsAPilot() throws {
        let made = try Self.awayWorld()
        var w = made.0
        let back = w.clock.minute + 2 * GameClock.minutesPerDay
        for p in w.ops.pilots.indices { w.ops.pilots[p].sickUntilMinute = back }
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: made.1)
        #expect(w.aircraft[0].flight == nil)
        #expect(w.aircraft[0].status == .boarding(until: back))
        #expect(w.news.contains { $0.kind == .noCrew })
    }

    @Test func aFreeAircraftHeldAtTheGateKeepsWhereItIsGoing() throws {
        var w = try Fixtures.world(mode: .easy)
        w.setPausePolicy(.never)
        w.aircraft[0].blockMinutesToday = 9 * 60
        let started = w.startFerry(index: 0, to: "YUB")
        #expect(started)
        #expect(w.aircraft[0].flight == nil)
        #expect(w.aircraft[0].ferryTargetStore == "YUB")
        w.advance(byMinutes: 2 * GameClock.minutesPerDay)
        #expect(w.aircraft[0].location == "YUB")
        #expect(w.aircraft[0].status == .idle)
        #expect(w.aircraft[0].ferryTargetStore == nil)
    }

    @Test func anEmptyHopFromABusyAirportGoesOnAOneOffSlotWhereTheAirlineHoldsNone() throws {
        var w = try Fixtures.world()
        w.setPausePolicy(.never)
        w.market.closures = []
        let yeg = try Fixtures.airport("YEG")
        #expect(w.needsSlots(yeg))
        #expect(w.slotsHeld(at: "YEG") == 0)
        w.aircraft[0].location = "YEG"
        let route = try w.createRoute(stops: ["YEV", "YUB"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        #expect(w.aircraft[0].flight?.isFerry == true, "no slots held at Edmonton, and still not stuck there")
    }

    @Test func anEmptyHopUsesTheAirlinesSlotsWhereItHoldsSome() throws {
        var w = try Fixtures.world()
        w.setPausePolicy(.never)
        w.market.closures = []
        w.aircraft[0].location = "YEG"
        w.ops.slots = [SlotHolding(airport: "YEG", daily: 1)]
        w.ops.slotsUsedToday = [SlotHolding(airport: "YEG", daily: 1)]
        let route = try w.createRoute(stops: ["YEV", "YUB"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        let tomorrowMorning = (w.clock.dayIndex + 1) * GameClock.minutesPerDay + 6 * 60
        #expect(w.aircraft[0].flight == nil)
        #expect(w.aircraft[0].status == .boarding(until: tomorrowMorning), "today's slot at Edmonton is used up")
    }

    // MARK: Giving up

    @Test func anAircraftThatCanNeverReachItsRouteGivesItUpAndSaysSo() throws {
        var w = try Fixtures.flyingWorld()
        w.setPausePolicy(.never)
        let route = w.routes[0].id
        // On Hawaii: no chain of stops a Caravan can fly reaches the Arctic from there.
        w.aircraft[0].location = "HNL"
        w.aircraft[0].status = .boarding(until: w.clock.minute)
        w.depart(0)
        #expect(w.aircraft[0].routeID == nil)
        #expect(w.aircraft[0].status == .idle)
        let listed = w.routes.first { $0.id == route }?.aircraftIDs ?? [-1]
        #expect(listed.isEmpty)
        let last = try #require(w.news.last)
        #expect(last.kind == .milestone)
        #expect(last.subject == "ferrygone:\(w.aircraft[0].registration):HNL")
        #expect(last.amount == FerryGiveUpReason.noWayThere.rawValue)
    }

    @Test func floatsOnARunwayCannotLeaveSoTheAircraftGivesUpItsRoute() throws {
        var w = try Self.juneWorld()
        w.aircraft[0].kits = [.floats]
        w.aircraft[0].location = "NUP"
        let route = try w.createRoute(stops: ["NUP", "SXP"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        // Now it stands on Bethel's runway with its floats on: it can never take off there.
        w.aircraft[0].location = "BET"
        w.aircraft[0].status = .boarding(until: w.clock.minute)
        w.depart(0)
        #expect(w.aircraft[0].routeID == nil)
        #expect(w.aircraft[0].status == .idle)
        let last = try #require(w.news.last)
        #expect(last.subject == "ferrygone:\(w.aircraft[0].registration):BET")
        #expect(last.amount == FerryGiveUpReason.cannotLeave.rawValue)
    }

    // MARK: Midnight

    @Test func aDepartureDueAtMidnightFliesOnTheNewDaysCrewHours() throws {
        var w = try Fixtures.world(mode: .easy)
        w.setPausePolicy(.never)
        let route = try w.createRoute(stops: ["YEV", "YUB"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        // At the gate until 00:00 with yesterday's crew hours all but used up: the leg to Tuktoyaktuk would go past them.
        let midnight = (w.clock.dayIndex + 1) * GameClock.minutesPerDay
        w.aircraft[0].blockMinutesToday = 9 * 60 - 10
        w.aircraft[0].status = .boarding(until: midnight)
        w.advance(toMinute: midnight + 1)
        switch w.aircraft[0].status {
        case .flying:
            #expect(w.aircraft[0].flight?.departedMinute == midnight, "it leaves at 00:00, not at 06:00 the day after")
            #expect(w.aircraft[0].blockMinutesToday < 9 * 60 - 10, "the leg counts towards the new day")
        case .grounded:
            break // The breakdown roll came up: the crew day did not hold it.
        default:
            Testing.Issue.record("expected it to leave at 00:00, got \(w.aircraft[0].status)")
        }
    }
}
