import Testing
@testable import CoreCatalog

@Suite struct AirportCatalogTests {
    @Test func loadsEveryRow() {
        #expect(AirportCatalog.all.count > 1400 && AirportCatalog.all.count < 1800, "one airport per area keeps the map clean")
        #expect(AirportCatalog.byCode.count == AirportCatalog.all.count, "airport codes must be unique")
        #expect(AirportCatalog.retired.count > 3000)
        #expect(Set(AirportCatalog.retired.keys).isDisjoint(with: AirportCatalog.byCode.keys), "a retired airport is never also on the map")
    }

    @Test func theMapKeepsCitiesAndRemotePlacesAndDropsRoadTowns() throws {
        for code in ["YEV", "YHI", "YCB", "YSY", "YUB", "YZF", "YVR", "YXY"] { #expect(AirportCatalog.byCode[code] != nil, "\(code) stays on the map") }
        for code in ["YXX", "YQZ"] {
            #expect(AirportCatalog.byCode[code] == nil, "\(code) is a road town and leaves the map")
            #expect(AirportCatalog.airport(code) != nil, "\(code) still loads for an older save")
        }
    }

    @Test func awayFromTheStartRegionsSmallAirportsAreWellApart() {
        // tools/data/declutter.py: 250 km apart (big cities 150 km); the start regions keep more places to fly to.
        let starts = StartRegions.all.flatMap(\.headquarters).compactMap { AirportCatalog.airport($0) }
        let far = AirportCatalog.all.filter { a in
            a.population < 500_000 && a.surface != .water && starts.allSatisfy { a.distanceKm(to: $0) > 900 }
        }
        var crowded = 0
        for (i, a) in far.enumerated() {
            for b in far[(i + 1)...] where a.distanceKm(to: b) < 200 { crowded += 1 }
        }
        #expect(far.count > 300)
        #expect(crowded < 10, "small airports closer than 200 km away from the start regions: \(crowded) pairs")
    }

    @Test func inuvikIsThere() throws {
        let yev = try #require(AirportCatalog.airport("YEV"))
        #expect(yev.city == "Inuvik")
        #expect(yev.country == "CA" && yev.region == "NT")
        #expect(yev.runwayFt == 6000 && yev.surface == .paved)
        #expect(yev.population > 2000 && yev.population < 5000)
        #expect(yev.shortName == "Inuvik Mike Zubko")
        #expect(yev.label == "Inuvik")
    }

    @Test func everyAirportHasValidData() {
        for a in AirportCatalog.all {
            #expect(a.latitude >= -90 && a.latitude <= 90 && a.longitude >= -180 && a.longitude <= 180, "\(a.code) position")
            #expect(a.population > 0, "\(a.code) population")
            #expect(!a.label.isEmpty && a.label.allSatisfy { $0.isASCII }, "\(a.code) label")
            #expect(a.name.allSatisfy { $0.isASCII }, "\(a.code) name must be ASCII for the pixel font")
            #expect(a.city.allSatisfy { $0.isASCII }, "\(a.code) city must be ASCII for the pixel font")
            #expect(CountryCatalog.country(a.country) != nil, "\(a.code) country \(a.country)")
            #expect(a.kind == .seaplane ? a.surface == .water : a.runwayFt > 0, "\(a.code) runway")
        }
    }

    @Test func labelsAreUniqueSoAListNeverShowsTwoOfTheSameName() {
        #expect(Set(AirportCatalog.all.map(\.label)).count == AirportCatalog.all.count)
    }

    @Test func oneAirportPerCityAndTownsKeepTheirOwnName() throws {
        let london = AirportCatalog.all.filter { $0.country == "GB" && $0.city == "London" }
        #expect(london.count == 1 && london.first?.code == "LHR", "London keeps one airport: Heathrow")
        for code in ["LGW", "STN", "LCY", "LTN", "LGA"] { #expect(AirportCatalog.airport(code) == nil, "\(code) is a second airport of a city that already has one") }
        let sachs = try #require(AirportCatalog.airport("YSY"))
        #expect(sachs.label == "Sachs Harbour", "a remote hamlet with scheduled service stays")
        let tuk = try #require(AirportCatalog.airport("YUB"))
        #expect(tuk.label == "Tuktoyaktuk")
        // No two airports of the same city name within 100 km of each other.
        var seen: [String: [Airport]] = [:]
        for a in AirportCatalog.all { seen["\(a.country)|\(a.city.lowercased())", default: []].append(a) }
        for (key, list) in seen where list.count > 1 {
            for i in 0..<list.count { for j in (i + 1)..<list.count { #expect(list[i].distanceKm(to: list[j]) >= 100, "\(key): \(list[i].code) and \(list[j].code)") } }
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
        #expect(countries.count > 190)
        #expect(AirportCatalog.all.filter { $0.kind == .large }.count > 550)
        #expect(AirportCatalog.all.filter { $0.surface == .gravel }.count > 100, "bush flying still has gravel strips")
        #expect(AirportCatalog.all.filter { $0.surface == .water }.count >= 10, "floatplanes still have lakes")
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
