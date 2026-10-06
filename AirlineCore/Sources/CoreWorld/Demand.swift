// CoreWorld/Demand.swift: how many people (and how much freight) want to travel between two airports. All airlines together.
import CoreCatalog
import CoreSim

public enum Demand {
    /// 0 for a town with roads and alternatives, up to 1 for a fly-in community on a gravel strip or a lake.
    /// In poorer countries bigger towns still count as fly-in (see `Tuning.isolationPopulationByWealth`).
    public static func isolation(_ airport: Airport) -> Double {
        let roads = Tuning.isolationPopulationByWealth[tier(of: airport) - 1]
        let remote = max(0.0, 1.0 - Double(airport.population) / roads)
        return remote * (airport.surface == .paved ? Tuning.pavedIsolationFactor : 1.0)
    }

    static func wealth(of airport: Airport) -> Int { CountryCatalog.country(airport.country)?.wealth ?? 3 }

    /// The wealth tier, kept inside 1...5 so it can index the tables.
    static func tier(of airport: Airport) -> Int { min(max(wealth(of: airport), 1), Tuning.propensity.count) }

    /// Trips per person per year from an airport: the country's habit or, for a fly-in community, at least the lifeline it needs,
    /// and more the more isolated it is.
    public static func propensity(_ airport: Airport) -> Double {
        let remote = isolation(airport)
        let habit = max(Tuning.propensity[tier(of: airport) - 1], Tuning.lifelinePropensity * remote)
        return habit * (1.0 + Tuning.isolationBoost * remote)
    }

    /// Passengers per day travelling one way from `a` to `b`, all airlines together, before seasons and competition.
    public static func passengersPerDay(from a: Airport, to b: Airport, distanceKm: Double) -> Double {
        let pa = propensity(a)
        let pb = propensity(b)
        let size = (Powers.eighths(Double(min(a.population, Tuning.populationCap)), Tuning.populationEighths) * Powers.eighths(Double(min(b.population, Tuning.populationCap)), Tuning.populationEighths)).squareRoot()
        return Tuning.demandConstant * (pa * pb).squareRoot() * size * Tuning.distanceShare.value(at: distanceKm) / 365.0
    }

    public static func passengersPerDay(from a: Airport, to b: Airport) -> Double {
        passengersPerDay(from: a, to: b, distanceKm: a.distanceKm(to: b))
    }

    /// Freight in kilograms per day from `a` to `b`: what the people at `b` need, far more for a fly-in community with no road.
    public static func cargoKgPerDay(from a: Airport, to b: Airport) -> Double {
        Tuning.cargoConstant * Powers.eighths(Double(min(b.population, Tuning.populationCap)), 7) * (Tuning.cargoBaseShare + Tuning.cargoIsolationShare * isolation(b))
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
