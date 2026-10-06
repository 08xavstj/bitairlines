// CoreWorld/FlightCosts.swift: what one flight costs this airline, after everything it has done to change that: fuel bought ahead,
// fuel depots, perks, the aircraft's age and condition.
import CoreCatalog
import CoreSim

extension World {
    /// Cost of flying one leg (fuel, crew, maintenance, fees), before any passenger or freight handling.
    mutating func legCost(type: AircraftType, aircraftIndex i: Int?, from a: Airport, to b: Airport, km: Double) -> Double {
        var wear = 1.0
        if let i { wear = Valuation.wearFactor(ageYears: aircraft[i].ageYears(atDay: clock.dayIndex), condition: aircraft[i].condition) }
        let costs = LegEconomics.cost(type: type, from: a, to: b, distanceKm: km, fuelIndex: fuelIndex(leaving: a.code),
                                      wearFactor: wear * maintenanceFactor, adjust: costAdjust)
        return max(0, costs.total - fuelStockCredit(type: type, blockHours: costs.blockHours))
    }

    /// The changes to standard leg costs this airline has earned (depots, perks).
    var costAdjust: CostAdjust {
        CostAdjust(depots: depotAirports, smallFieldFeeFactor: has(.smallFieldDeal) ? 0.75 : 1.0)
    }

    /// Cost per passenger at the two airports, after service level and perks.
    func passengerCost(from a: Airport, to b: Airport, service: ServiceLevel) -> Double {
        let fees = LegEconomics.perPassenger(from: a, to: b, adjust: costAdjust)
        return max(0, fees + service.costPerPassenger)
    }
}
