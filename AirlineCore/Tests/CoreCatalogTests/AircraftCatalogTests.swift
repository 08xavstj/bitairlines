import Testing
@testable import CoreCatalog

@Suite struct AircraftCatalogTests {
    @Test func everyRowParses() {
        let lines = AircraftRows.rows.split(separator: "\n").count
        #expect(AircraftCatalog.all.count == lines, "a row failed to parse")
        #expect(AircraftCatalog.all.count == 52)
        #expect(AircraftCatalog.byID.count == AircraftCatalog.all.count, "aircraft ids must be unique")
    }

    @Test func specsArePlausible() {
        for t in AircraftCatalog.all {
            #expect(t.seats > 0 && t.rangeKm >= 600 && t.cruiseKph >= 180 && t.fuelBurnKgPerHour > 0, "\(t.id)")
            #expect(t.priceUSD >= 400_000 && t.maxTakeoffKg > 1000 && t.maintenanceUSDPerHour > 0, "\(t.id)")
            #expect((1...7).contains(t.level) && (1...3).contains(t.pilots), "\(t.id)")
            #expect(t.paved || t.gravel || t.water, "\(t.id) must operate somewhere")
            #expect(!(t.water && (t.paved || t.gravel)), "\(t.id): float variants are separate models")
            #expect(t.water ? t.runwayFt == 0 : t.runwayFt >= 700, "\(t.id) runway")
        }
    }

    @Test func biggerAircraftCostMoreToFlyAndBuy() throws {
        let tw = try #require(AircraftCatalog.type("dhc6")), b738 = try #require(AircraftCatalog.type("b738")), a388 = try #require(AircraftCatalog.type("a388"))
        #expect(tw.priceUSD < b738.priceUSD && b738.priceUSD < a388.priceUSD)
        #expect(tw.fuelBurnKgPerHour < b738.fuelBurnKgPerHour && b738.fuelBurnKgPerHour < a388.fuelBurnKgPerHour)
        #expect(tw.seats < b738.seats && b738.seats < a388.seats)
    }

    @Test func startingFleetIsBushFlying() {
        let starters = AircraftCatalog.available(atLevel: 1).map(\.id)
        for id in ["c172", "c208", "dhc6", "dc3", "dhc2", "dhc3"] { #expect(starters.contains(id), "\(id) should be available at level 1") }
        #expect(!starters.contains("b738"))
    }

    @Test func gravelStripsNeedGravelAircraft() throws {
        let tuk = try #require(AirportCatalog.airport("YUB")), tw = try #require(AircraftCatalog.type("dhc6")), b738 = try #require(AircraftCatalog.type("b738"))
        #expect(tuk.surface == .gravel)
        #expect(tw.canLand(at: tuk))
        #expect(!b738.canLand(at: tuk))
    }

    @Test func floatplanesNeedWater() throws {
        let yev = try #require(AirportCatalog.airport("YEV")), floats = try #require(AircraftCatalog.type("dhc6f"))
        #expect(!floats.canLand(at: yev))
        let water = AirportCatalog.all.first { $0.surface == .water }
        #expect(water != nil)
        if let water { #expect(floats.canLand(at: water)) }
    }

    @Test func suitableAircraftForARemoteHop() throws {
        let yev = try #require(AirportCatalog.airport("YEV")), yub = try #require(AirportCatalog.airport("YUB"))
        let ids = AircraftCatalog.suitable(from: yev, to: yub, km: yev.distanceKm(to: yub)).map(\.id)
        #expect(ids.contains("dhc6") && ids.contains("c208") && ids.contains("dc3"))
        #expect(!ids.contains("b738") && !ids.contains("dhc6f"))
    }

    @Test func crewRules() throws {
        let c208 = try #require(AircraftCatalog.type("c208")), a320 = try #require(AircraftCatalog.type("a320"))
        #expect(c208.cabinCrew == 0 && c208.crew == 1)
        #expect(a320.cabinCrew == 4 && a320.crew == 6)
    }

    @Test func blockTimeGrowsWithDistance() throws {
        let tw = try #require(AircraftCatalog.type("dhc6"))
        #expect(tw.blockHours(km: 127) < tw.blockHours(km: 1000))
        #expect(abs(tw.blockHours(km: 337) - 1.3) < 0.01)
    }
}
