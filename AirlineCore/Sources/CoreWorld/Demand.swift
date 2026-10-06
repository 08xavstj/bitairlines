// CoreWorld/Demand.swift: how many people (and how much freight) want to travel between two airports. All airlines together.
import CoreCatalog
import CoreSim

public enum Demand {
    /// 0 for a town with roads and alternatives, up to 1 for a fly-in community on a gravel strip or a lake.
    public static func isolation(_ airport: Airport) -> Double {
        let remote = max(0.0, 1.0 - Double(airport.population) / Tuning.isolationPopulation)
        return remote * (airport.surface == .paved ? Tuning.pavedIsolationFactor : 1.0)
    }

    static func wealth(of airport: Airport) -> Int { CountryCatalog.country(airport.country)?.wealth ?? 3 }

    /// Passengers per day travelling one way from `a` to `b`, all airlines together, before seasons and competition.
    public static func passengersPerDay(from a: Airport, to b: Airport, distanceKm: Double) -> Double {
        let pa = Tuning.propensity[wealth(of: a) - 1] * (1.0 + Tuning.isolationBoost * isolation(a))
        let pb = Tuning.propensity[wealth(of: b) - 1] * (1.0 + Tuning.isolationBoost * isolation(b))
        let size = (Powers.eighths(Double(a.population), Tuning.populationEighths) * Powers.eighths(Double(b.population), Tuning.populationEighths)).squareRoot()
        return Tuning.demandConstant * (pa * pb).squareRoot() * size * Tuning.distanceShare.value(at: distanceKm) / 365.0
    }

    public static func passengersPerDay(from a: Airport, to b: Airport) -> Double {
        passengersPerDay(from: a, to: b, distanceKm: a.distanceKm(to: b))
    }

    /// Freight in kilograms per day from `a` to `b`: what the people at `b` need, far more for a fly-in community with no road.
    public static func cargoKgPerDay(from a: Airport, to b: Airport) -> Double {
        Tuning.cargoConstant * Powers.eighths(Double(b.population), 7) * (Tuning.cargoBaseShare + Tuning.cargoIsolationShare * isolation(b))
    }
}

public enum Fares {
    /// The going one-way economy fare in US dollars between two airports (a fare multiplier of 1.0 charges exactly this).
    public static func market(from a: Airport, to b: Airport, distanceKm: Double) -> Double {
        let remote = (Demand.isolation(a) + Demand.isolation(b)) / 2.0
        return Tuning.fareScale * Tuning.fareByDistance.value(at: distanceKm) * (1.0 + Tuning.isolationFarePremium * remote)
    }

    /// Freight rate in US dollars per kilogram.
    public static func cargoRate(distanceKm: Double) -> Double { Tuning.cargoRateByDistance.value(at: distanceKm) }
}
