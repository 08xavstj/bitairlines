// CoreWorld/FuelMarket.swift: buying fuel ahead. The airline pays today's price for a stock of fuel; flights draw on the stock first.
// Fuel in the tanks is something the airline keeps, so buying it is booked as an investment, not a running cost. A covered flight
// is charged its normal fuel bill with the fuel it used priced at what was paid for it, so buying cheap saves money and buying
// dear costs money, while the extra for flying fuel to remote strips is still paid; the route books see the same cost.
// The price drifts a little every day (and a lot in an oil shock), and the last few months are kept for a chart.
import CoreCatalog
import CoreSim

public struct FuelStock: Sendable, Hashable, Codable {
    /// Kilograms bought ahead and not yet burned.
    public var kg: Double = 0
    /// The price index the stock was bought at (an average when bought in several lots).
    public var priceIndex: Double = 1.0
    /// Kilograms of the stock that were booked as an investment when bought. Older saves booked fuel as a running cost on the day
    /// it was bought; that part (the rest of `kg`) is not charged again when it is burned. Missing from older saves.
    var investedKgStore: Double?

    public init() {}

    /// Kilograms in the tanks whose price is still to be charged to the flights that burn them.
    public var investedKg: Double {
        get { min(kg, investedKgStore ?? 0) }
        set { investedKgStore = newValue > 0 ? newValue : nil }
    }
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
        spendOnInvestment(price)
        var stock = ops.fuel
        let invested = stock.investedKg
        let total = stock.kg + kg
        stock.priceIndex = (stock.kg * stock.priceIndex + kg * market.fuelIndex) / total
        stock.kg = total
        stock.investedKg = invested + kg
        ops.fuel = stock
        addNews(.fuelBought, subject: "fuel", amount: Int(kg))
    }

    /// Takes the fuel for one flight out of the stock when there is enough, and returns the credit taken off the flight's fuel
    /// bill: what that fuel would cost today, less what was paid for it. The paid part leaves the stock (the investment) and goes
    /// into the flight's cost, so the airline's money is the same and the flight and its route carry the fuel at the price paid.
    mutating func fuelStockCredit(type: AircraftType, blockHours: Double) -> Double {
        let needed = Double(type.fuelBurnKgPerHour) * blockHours
        var stock = ops.fuel
        guard needed > 0, stock.kg >= needed else { return 0 }
        let fromInvested = min(needed, stock.investedKg)
        let paid = Int((fromInvested * Tuning.jetFuelPerKg * stock.priceIndex).rounded())
        stock.investedKg = stock.investedKg - fromInvested
        stock.kg -= needed
        ops.fuel = stock
        if paid > 0 {
            // The stock is drawn down: the money it held comes back now and the flight is charged it when it lands.
            airline.cash += paid
            airline.stats.expenses -= paid
            today.investments -= paid
        }
        return needed * Tuning.jetFuelPerKg * market.fuelIndex - Double(paid)
    }

    /// The fuel price index a flight leaving `code` pays (the home fuel deal makes home cheaper).
    func fuelIndex(leaving code: String) -> Double {
        code == airline.home && has(.homeFuelDeal) ? market.fuelIndex * 0.85 : market.fuelIndex
    }

    /// Once a day: a little noise on the price, and a line on the chart.
    mutating func dailyFuelMarket() {
        // A little noise each day, and a gentle pull back towards normal so the price wanders but does not drift away.
        let noise = ops.rng.uniform(-0.012, 0.012)
        let pull = (1.0 - market.fuelIndex) * 0.01
        market.fuelIndex = min(2.4, max(0.5, market.fuelIndex * (1.0 + noise) + pull))
        ops.fuelHistory.append(market.fuelIndex)
        if ops.fuelHistory.count > World.fuelHistoryDays { ops.fuelHistory.removeFirst(ops.fuelHistory.count - World.fuelHistoryDays) }
    }
}
