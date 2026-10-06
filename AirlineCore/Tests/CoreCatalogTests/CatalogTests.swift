import Testing
@testable import CoreCatalog

@Suite struct AirportCatalogTests {
    @Test func loadsEveryRow() {
        #expect(AirportCatalog.all.count > 6000)
        #expect(AirportCatalog.byCode.count == AirportCatalog.all.count, "airport codes must be unique")
    }

    @Test func inuvikIsThere() throws {
        let yev = try #require(AirportCatalog.airport("YEV"))
        #expect(yev.city == "Inuvik")
        #expect(yev.country == "CA" && yev.region == "NT")
        #expect(yev.runwayFt == 6000 && yev.surface == .paved)
        #expect(yev.population > 2000 && yev.population < 5000)
        #expect(yev.shortName == "Inuvik Mike Zubko")
    }

    @Test func everyAirportHasValidData() {
        for a in AirportCatalog.all {
            #expect(a.latitude >= -90 && a.latitude <= 90 && a.longitude >= -180 && a.longitude <= 180, "\(a.code) position")
            #expect(a.population > 0, "\(a.code) population")
            #expect(a.name.allSatisfy { $0.isASCII }, "\(a.code) name must be ASCII for the pixel font")
            #expect(a.city.allSatisfy { $0.isASCII }, "\(a.code) city must be ASCII for the pixel font")
            #expect(CountryCatalog.country(a.country) != nil, "\(a.code) country \(a.country)")
            #expect(a.kind == .seaplane ? a.surface == .water : a.runwayFt > 0, "\(a.code) runway")
        }
    }

    @Test func distanceBetweenAirports() throws {
        let yev = try #require(AirportCatalog.airport("YEV")), yub = try #require(AirportCatalog.airport("YUB"))
        #expect(abs(yev.distanceKm(to: yub) - 127) < 3)
    }

    @Test func nearestFindsTheRemoteNeighbours() {
        let near = AirportCatalog.nearest(latitude: 68.3042, longitude: -133.4830, limit: 3)
        #expect(near.first?.code == "YEV")
        #expect(near.count == 3)
    }

    @Test func coverageIsWorldWide() {
        let countries = Set(AirportCatalog.all.map(\.country))
        #expect(countries.count > 200)
        #expect(AirportCatalog.all.filter { $0.kind == .large }.count > 900)
        #expect(AirportCatalog.all.filter { $0.surface == .gravel }.count > 500, "bush flying needs plenty of gravel strips")
    }
}

@Suite struct CountryCatalogTests {
    @Test func loadsAllCountries() {
        #expect(CountryCatalog.all.count == 233)
        for c in CountryCatalog.all { #expect((1...5).contains(c.wealth), "\(c.code) wealth") }
    }

    @Test func groupsCoverTheWorld() {
        for group in RegionGroup.allCases { #expect(!AirportCatalog.inGroup(group).isEmpty, "\(group.rawValue) has airports") }
    }
}

@Suite struct LandMaskTests {
    @Test func knownPlaces() {
        let m = LandMask.world
        #expect(m.isLand(latitude: 48.85, longitude: 2.35), "Paris")
        #expect(m.isLand(latitude: 68.30, longitude: -133.48), "Inuvik")
        #expect(m.isLand(latitude: -25.0, longitude: 135.0), "central Australia")
        #expect(m.isLand(latitude: 40.7, longitude: -74.0), "New York")
        #expect(!m.isLand(latitude: 0, longitude: -30), "mid Atlantic")
        #expect(!m.isLand(latitude: -40, longitude: -120), "south Pacific")
        #expect(!m.isLand(latitude: 30, longitude: 150), "Pacific east of Japan")
    }

    @Test func mostScheduledAirportsSitOnOrNextToLand() {
        let m = LandMask.world
        var onLand = 0
        for a in AirportCatalog.all where m.isLand(latitude: a.latitude, longitude: a.longitude) { onLand += 1 }
        #expect(Double(onLand) / Double(AirportCatalog.all.count) > 0.93)
    }
}
