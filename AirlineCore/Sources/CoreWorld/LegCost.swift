// CoreWorld/LegCost.swift: what one flight (one leg) costs to operate, in US dollars. Passenger-related costs are added per boarded passenger.
import CoreCatalog
import CoreSim

public struct LegCost: Sendable, Equatable {
    public var blockHours: Double
    public var fuel: Double
    public var crew: Double
    public var maintenance: Double
    public var landing: Double
    public var navigation: Double

    public var total: Double { fuel + crew + maintenance + landing + navigation }
}

public enum LegEconomics {
    /// - Parameters:
    ///   - fuelIndex: the fuel price relative to the baseline (1.0 is the baseline).
    ///   - wearFactor: maintenance cost multiplier for an ageing or run-down aircraft (1.0 is new).
    public static func cost(type: AircraftType, from a: Airport, to b: Airport, distanceKm: Double, fuelIndex: Double = 1.0, wearFactor: Double = 1.0) -> LegCost {
        let block = type.blockHours(km: distanceKm)
        let fuelPrice = (type.engine == .piston ? Tuning.avgasPerKg : Tuning.jetFuelPerKg) * fuelIndex
        let premium = 1.0 + ((Tuning.fuelPremium[a.kind] ?? 0) + (Tuning.fuelPremium[b.kind] ?? 0)) / 2.0
        let fuel = Double(type.fuelBurnKgPerHour) * block * fuelPrice * premium
        let crew = (Double(type.pilots) * Tuning.pilotPerBlockHour + Double(type.cabinCrew) * Tuning.cabinCrewPerBlockHour) * block
        let maintenance = Double(type.maintenanceUSDPerHour) * block * wearFactor
        let tonnes = Double(type.maxTakeoffKg) / 1000.0
        let landing = max(Tuning.minimumLandingFee, (Tuning.landingFeePerTonne[b.kind] ?? 4) * tonnes)
        let navigation = Tuning.navigationPerKm * (tonnes / 50.0).squareRoot() * distanceKm
        return LegCost(blockHours: block, fuel: fuel, crew: crew, maintenance: maintenance, landing: landing, navigation: navigation)
    }

    /// Cost per boarded passenger: ground handling, catering and service, plus the passenger charge at the two airports.
    public static func perPassenger(from a: Airport, to b: Airport) -> Double {
        Tuning.handlingPerPassenger + ((Tuning.passengerFee[a.kind] ?? 2) + (Tuning.passengerFee[b.kind] ?? 2)) / 2.0
    }

    /// Fixed cost per day of keeping one aircraft in the fleet (admin and insurance).
    public static func fixedPerDay(type: AircraftType) -> Double {
        Tuning.adminPerAircraftPerDay + Tuning.insuranceShareOfPricePerYear * Double(type.priceUSD) / 365.0
    }
}
