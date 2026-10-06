import Testing
import CoreCatalog
@testable import CoreWorld

@Suite struct BasesAndKitsTests {
    @Test func aFuelDepotCostsMoneyAndUpkeepAndAddsStorage() throws {
        var w = try Fixtures.world()
        let yev = try Fixtures.airport("YEV")
        let cash = w.airline.cash
        let price = w.facilityPrice(.fuelDepot, at: yev)
        let storage = w.fuelCapacityKg
        try w.build(.fuelDepot, at: "YEV")
        #expect(w.airline.cash == cash - price)
        #expect(w.ops.bases.count == 1 && w.ops.bases[0].has(.fuelDepot))
        #expect(w.fuelCapacityKg > storage)
        #expect(w.baseUpkeepPerDay == w.facilityUpkeep(.fuelDepot, at: yev))
        #expect(throws: WorldError.alreadyBuilt) { try w.build(.fuelDepot, at: "YEV") }
        let depot = w.costAdjust
        #expect(depot.fuelPremium(at: yev) == 0, "no remote premium where the airline has its own fuel")
    }

    @Test func lightsPavingAndALongerRunwayChangeWhatCanLand() throws {
        var w = try Fixtures.world()
        w.airline.cash = 20_000_000
        let yub = try Fixtures.airport("YUB")
        let yev = try Fixtures.airport("YEV")
        #expect(!w.isLit(yub))
        try w.build(.lights, at: "YUB")
        #expect(w.isLit(yub))
        #expect(throws: WorldError.alreadyBuilt) { try w.build(.lights, at: "YEV") }

        #expect(w.facilityProblem(.paving, at: "YEV") == .cannotBuildHere, "already paved")
        try w.build(.paving, at: "YUB")
        #expect(w.surface(at: yub) == .paved)

        let jet = try Fixtures.type("b738")
        #expect(!w.canUse(type: jet, at: yev))
        try w.build(.runwayExtension, at: "YEV")
        #expect(w.runwayFt(at: yev) == yev.runwayFt + Tuning.runwayExtensionFt)
        #expect(w.canUse(type: jet, at: yev), "6,000 plus 1,500 feet is enough for a 737")
    }

    @Test func aHubNeedsTheSecondCertificate() throws {
        var w = try Fixtures.world()
        #expect(w.facilityProblem(.hubTerminal, at: "YEV") == .levelTooLow(required: 2))
        w.airline.level = 2
        w.airline.cash = 20_000_000
        try w.build(.hubTerminal, at: "YEV")
        #expect(w.hubs == ["YEV"])
    }

    @Test func floatsPutAnAircraftOnTheWaterAndOffItsRunwayRoute() throws {
        var w = try Fixtures.flyingWorld()
        let id = w.aircraft[0].id
        #expect(w.kitProblem(.gravelKit, aircraftID: id) == .kitDoesNotFit, "a Caravan already uses gravel")
        try w.fit(.floats, aircraftID: id)
        #expect(w.aircraft[0].kits == [.floats])
        if case .maintenance = w.aircraft[0].status {} else { Testing.Issue.record("fitting takes the aircraft into the hangar") }
        let cap = try #require(w.aircraft[0].capability)
        #expect(cap.water && !cap.paved && !cap.gravel)
        #expect(w.aircraft[0].routeID == nil && w.routes[0].aircraftIDs.isEmpty, "it can no longer use the runways on its route")
        // Amphibious floats replace plain floats.
        w.advance(byMinutes: 4 * 1440)
        try w.fit(.amphibious, aircraftID: id)
        #expect(w.aircraft[0].kits == [.amphibious])
    }

    @Test func aFreighterConversionSwapsSeatsForFreight() throws {
        var w = try Fixtures.world()
        let id = w.aircraft[0].id
        let hold = w.aircraft[0].cargoKg
        try w.fit(.freighter, aircraftID: id)
        #expect(w.aircraft[0].seats == 0)
        #expect(w.aircraft[0].cargoKg > hold)
    }
}
