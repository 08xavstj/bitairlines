// CoreWorld/FuelMarket.swift: buying fuel ahead. The airline pays today's price for a stock of fuel; flights draw on the stock first.
// A covered flight is charged its normal fuel bill minus what the fuel it used is worth today, so buying cheap saves money and
// buying dear costs money, while the extra for flying fuel to remote strips is still paid. The price drifts a little every day
// (and a lot in an oil shock), and the last few months are kept for a chart.
import CoreCatalog
import CoreSim

public struct FuelStock: Sendable, Hashable, Codable {
    /// Kilograms bought ahead and not yet burned.
    public var kg: Double = 0
    /// The price index the stock was bought at (an average when bought in several lots).
    public var priceIndex: Double = 1.0

    public init() {}
}

extension World {
    /// Days of price history kept for the chart.
    public static let fuelHistoryDays = 120

    /// How much fuel the airline can hold: a little at head office, much more with fuel depots at its bases.
    public var fuelCapacityKg: Double {
        Tuning.fuelStorageBaseKg + Tuning.fuelStoragePerDepotKg * Double(ops.bases.filter { $0.has(.fuelDepot) }.count)
    }

    /// What `kg` of fuel costs bought ahead today.
    public func fuelPrice(kg: Double) -> Int { Int((kg * Tuning.jetFuelPerKg * market.fuelIndex).rounded()) }

    /// Buys fuel at today's price into the stock.
    public mutating func buyFuel(kg: Double) throws {
        guard kg >= 1000 else { throw WorldError.invalidAmount }
        guard ops.fuel.kg + kg <= fuelCapacityKg + 0.5 else { throw WorldError.fuelStorageFull(capacityKg: Int(fuelCapacityKg)) }
        let price = fuelPrice(kg: kg)
        guard airline.cash >= price else { throw WorldError.notEnoughCash(needed: price) }
        spendOnOverhead(price)
        let total = ops.fuel.kg + kg
        ops.fuel.priceIndex = (ops.fuel.kg * ops.fuel.priceIndex + kg * market.fuelIndex) / total
        ops.fuel.kg = total
        addNews(.fuelBought, subject: "fuel", amount: Int(kg))
    }

    /// Takes the fuel for one flight out of the stock when there is enough, and returns what that fuel is worth at today's price
    /// (the credit taken off the flight's fuel bill).
    mutating func fuelStockCredit(type: AircraftType, blockHours: Double) -> Double {
        let needed = Double(type.fuelBurnKgPerHour) * blockHours
        guard needed > 0, ops.fuel.kg >= needed else { return 0 }
        ops.fuel.kg -= needed
        return needed * Tuning.jetFuelPerKg * market.fuelIndex
    }

    /// The fuel price index a flight leaving `code` pays (the home fuel deal makes home cheaper).
    func fuelIndex(leaving code: String) -> Double {
        code == airline.home && has(.homeFuelDeal) ? market.fuelIndex * 0.85 : market.fuelIndex
    }

    /// Once a day: a little noise on the price, and a line on the chart.
    mutating func dailyFuelMarket() {
        let noise = ops.rng.uniform(-0.012, 0.012)
        market.fuelIndex = min(2.4, max(0.5, market.fuelIndex * (1.0 + noise)))
        ops.fuelHistory.append(market.fuelIndex)
        if ops.fuelHistory.count > World.fuelHistoryDays { ops.fuelHistory.removeFirst(ops.fuelHistory.count - World.fuelHistoryDays) }
    }
}
