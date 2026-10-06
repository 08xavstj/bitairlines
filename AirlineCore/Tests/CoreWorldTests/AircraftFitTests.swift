import Testing
import CoreCatalog
@testable import CoreWorld

@Suite struct AircraftFitTests {
    private func type(_ id: String) throws -> AircraftType { try #require(AircraftCatalog.type(id)) }

    private func airport(_ test: (Airport) -> Bool) throws -> Airport { try #require(AirportCatalog.all.first(where: test)) }

    @Test func theStarterFitsHomeAndTheNetworkStartsAtHome() throws {
        let w = try Fixtures.world()
        let fit = w.fit(of: try type("c208"))
        #expect(w.networkAirports.first == "YEV")
        #expect(fit.airports.first?.code == "YEV" && fit.fitsAll && fit.levelNeeded == nil)
    }

    @Test func routeStopsAndBasesJoinTheNetwork() throws {
        var w = try Fixtures.world()
        _ = try w.createRoute(stops: ["YEV", "YUB"])
        Fixtures.light(&w, "YSY")
        #expect(w.networkAirports == ["YEV", "YSY", "YUB"])
    }

    @Test func aBigTypeShowsTheLevelItNeeds() throws {
        let w = try Fixtures.world()
        #expect(w.fit(of: try type("a320")).levelNeeded == 5)
    }

    @Test func lakesNeedFloatsOrAreOutOfReach() throws {
        let w = try Fixtures.world()
        let lake = try airport { $0.surface == .water }
        #expect(w.needs(of: try type("c208"), at: lake) == [.floats])
        #expect(w.needs(of: try type("b1900"), at: lake) == [.cannotUseWater])
        #expect(w.needs(of: try type("c208f"), at: lake).isEmpty)
    }

    @Test func aFloatplaneCannotUseARunway() throws {
        let w = try Fixtures.world()
        let strip = try airport { $0.surface == .paved && $0.runwayFt >= 5000 }
        #expect(w.needs(of: try type("c208f"), at: strip) == [.cannotUseRunway])
    }

    @Test func gravelNeedsAKitOrPaving() throws {
        let w = try Fixtures.world()
        let gravel = try airport { $0.surface == .gravel && $0.runwayFt >= 5000 }
        #expect(w.needs(of: try type("dh8a"), at: gravel) == [.gravelKit])
        #expect(w.needs(of: try type("b1900"), at: gravel) == [.paving])
    }

    @Test func shortRunwaysNameTheCheapestFix() throws {
        let w = try Fixtures.world()
        // A Beech 1900 needs 3,200 ft; with the STOL kit 2,400 ft.
        let mid = try airport { $0.surface == .paved && $0.runwayFt >= 2600 && $0.runwayFt < 3200 }
        #expect(w.needs(of: try type("b1900"), at: mid) == [.stolKit])
        // An ERJ 145 needs 5,800 ft and takes no STOL kit; the extension adds 1,500 ft.
        let near = try airport { $0.surface == .paved && $0.runwayFt >= 4400 && $0.runwayFt < 5800 }
        #expect(w.needs(of: try type("e145"), at: near) == [.runwayExtension])
        let short = try airport { $0.surface == .paved && $0.runwayFt >= 2000 && $0.runwayFt < 4000 }
        #expect(w.needs(of: try type("e145"), at: short) == [.runwayTooShort(byFt: 5800 - short.runwayFt - 1500)])
    }

    @Test func deliveriesTakeHoursNotDays() throws {
        var w = try Fixtures.world(difficulty: .easy)
        let listing = try #require(w.market.listings.first { (AircraftCatalog.type($0.typeID)?.level ?? 9) <= 1 && $0.price < w.airline.cash })
        #expect(Valuation.usedDeliveryMinutes(listing) <= 18 * 60)
        #expect(Valuation.newDeliveryMinutes(level: 7) <= 4 * 1440)
        let id = try w.buyUsed(listingID: listing.id)
        w.advance(byMinutes: 18 * 60)
        #expect(w.aircraft.first { $0.id == id }?.isDelivered == true)
    }
}
