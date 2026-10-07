import Testing
import Foundation
import CoreCatalog
@testable import CoreWorld

@Suite struct FlightBookingTests {
    /// Moving an aircraft to another route while it is in the air must not lose the flight: it lands and is booked to the route it took off for.
    @Test func aLegFlownForARouteIsBookedToItEvenAfterAMoveInTheAir() throws {
        var w = try Fixtures.flyingWorld()
        for _ in 0..<3000 {
            if case .flying = w.aircraft[0].status { break }
            w.advance(byMinutes: 5)
        }
        guard case .flying = w.aircraft[0].status else { Issue.record("the aircraft should be flying its first leg"); return }
        let first = w.routes[0].id
        let other = try w.createRoute(stops: ["YEV", "YSY"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: other)
        for _ in 0..<3000 {
            if case .flying = w.aircraft[0].status { w.advance(byMinutes: 5) } else { break }
        }
        let flownFirst = w.routes.first { $0.id == first }?.flights ?? -1
        let flownOther = w.routes.first { $0.id == other }?.flights ?? -1
        #expect(flownFirst == 1)
        #expect(flownOther == 0)
        #expect(w.airline.stats.flights == 1)
    }

    @Test func anOlderSaveWithoutTheRouteOnTheFlightStillLoads() throws {
        let json = """
        {"from":"YEV","to":"YUB","departedMinute":10,"distanceKm":150,"passengers":4,"cargoKg":0,"revenue":1000,"cost":500,"isFerry":false}
        """
        let flight = try JSONDecoder().decode(Flight.self, from: Data(json.utf8))
        #expect(flight.routeIDStore == nil && flight.passengers == 4)
    }
}
