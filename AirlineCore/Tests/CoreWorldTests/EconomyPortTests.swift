import Testing
import CoreCatalog
import CoreSim
@testable import CoreWorld

/// The expected numbers come from the Python prototypes (tools/sim/demand_proto.py and route_proto.py). If a test here fails after an
/// intended balance change, update the prototype and these numbers together.
@Suite struct EconomyPortTests {
    func airport(_ code: String) throws -> Airport { try #require(AirportCatalog.airport(code)) }
    func close(_ a: Double, _ b: Double, tolerance: Double = 2e-4) -> Bool { abs(a - b) <= tolerance * max(1, abs(b)) }

    @Test func powersMatchTheirDefinition() {
        #expect(close(Powers.eighths(10000, 7), 3162.2776601683795, tolerance: 1e-9))
        #expect(close(Powers.eighths(81, 4), 9.0, tolerance: 1e-9))
        #expect(close(Powers.eighths(16, 8), 16.0, tolerance: 1e-12))
        #expect(close(Powers.oneAndAHalf(4), 8.0, tolerance: 1e-12))
    }

    @Test func linearTableInterpolates() {
        let t = LinearTable([(0, 0), (10, 100), (20, 100), (30, 0)])
        #expect(t.value(at: -5) == 0)
        #expect(t.value(at: 5) == 50)
        #expect(t.value(at: 15) == 100)
        #expect(t.value(at: 25) == 50)
        #expect(t.value(at: 99) == 0)
    }

    @Test func demandMatchesThePrototype() throws {
        let yev = try airport("YEV"), yzf = try airport("YZF"), yub = try airport("YUB"), yeg = try airport("YEG")
        let lhr = try airport("LHR"), jfk = try airport("JFK"), syd = try airport("SYD"), mel = try airport("MEL")
        #expect(close(Demand.passengersPerDay(from: yev, to: yzf), 40.457266))
        #expect(close(Demand.passengersPerDay(from: yev, to: yub), 7.558832))
        #expect(close(Demand.passengersPerDay(from: lhr, to: jfk), 4884.366686))
        #expect(close(Demand.passengersPerDay(from: syd, to: mel), 11898.537329))
        #expect(close(Demand.passengersPerDay(from: yzf, to: yeg), 448.173116))
    }

    @Test func demandIsSymmetricForTheSameWealthAndSize() throws {
        let a = try airport("YEV"), b = try airport("YZF")
        #expect(close(Demand.passengersPerDay(from: a, to: b), Demand.passengersPerDay(from: b, to: a)))
    }

    @Test func isolationAndCargoMatchThePrototype() throws {
        let yev = try airport("YEV"), yub = try airport("YUB"), lhr = try airport("LHR"), jfk = try airport("JFK")
        #expect(close(Demand.isolation(yev), 0.500850, tolerance: 1e-4))
        #expect(close(Demand.isolation(yub), 0.951100, tolerance: 1e-4))
        #expect(Demand.isolation(lhr) == 0)
        #expect(close(Demand.cargoKgPerDay(from: yev, to: yub), 219.850050))
        #expect(close(Demand.cargoKgPerDay(from: lhr, to: jfk), 21889.442508))
    }

    @Test func faresMatchThePrototype() throws {
        let yev = try airport("YEV"), yzf = try airport("YZF"), yub = try airport("YUB")
        #expect(close(Fares.market(from: yev, to: yzf, distanceKm: yev.distanceKm(to: yzf)), 263.352434))
        #expect(close(Fares.market(from: yev, to: yub, distanceKm: yev.distanceKm(to: yub)), 121.397139))
    }

    @Test func legCostsMatchThePrototype() throws {
        let tw = try #require(AircraftCatalog.type("dhc6"))
        let cv = try #require(AircraftCatalog.type("c208"))
        let b738 = try #require(AircraftCatalog.type("b738"))
        let yev = try airport("YEV"), yzf = try airport("YZF"), yub = try airport("YUB"), yeg = try airport("YEG")

        let a = LegEconomics.cost(type: tw, from: yev, to: yzf, distanceKm: yev.distanceKm(to: yzf))
        #expect(close(a.blockHours, 3.5284, tolerance: 1e-4))
        #expect(close(a.fuel, 1125.5685))
        #expect(close(a.crew, 564.5485))
        #expect(close(a.maintenance, 987.9598))
        #expect(close(a.landing, 45.36))
        #expect(close(a.navigation, 329.7388))
        #expect(close(a.total, 3053.1756))

        let b = LegEconomics.cost(type: cv, from: yev, to: yub, distanceKm: yev.distanceKm(to: yub))
        #expect(close(b.total, 410.6140))
        #expect(b.landing == 40)

        let c = LegEconomics.cost(type: b738, from: yzf, to: yeg, distanceKm: yzf.distanceKm(to: yeg))
        #expect(close(c.total, 9526.6618))
        #expect(close(c.landing, 1106))
    }

    @Test func fuelIndexScalesFuelOnly() throws {
        let tw = try #require(AircraftCatalog.type("dhc6"))
        let a = try airport("YEV"), b = try airport("YUB")
        let base = LegEconomics.cost(type: tw, from: a, to: b, distanceKm: 127)
        let dear = LegEconomics.cost(type: tw, from: a, to: b, distanceKm: 127, fuelIndex: 1.5)
        #expect(close(dear.fuel, base.fuel * 1.5, tolerance: 1e-9))
        #expect(dear.crew == base.crew)
        #expect(dear.maintenance == base.maintenance)
    }

    @Test func fixedCostGrowsWithAircraftValue() throws {
        let tw = try #require(AircraftCatalog.type("dhc6")), a388 = try #require(AircraftCatalog.type("a388"))
        #expect(LegEconomics.fixedPerDay(type: tw) < LegEconomics.fixedPerDay(type: a388))
    }
}
