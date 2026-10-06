// CoreWorld/Forecast.swift: what a route would earn, before the player commits. A steady-state version of what the simulation does every day:
// demand share, patience, seats, freight, fares, leg costs and the aircraft it takes. Checked against real simulated years in ForecastTests.
import CoreCatalog
import CoreSim

public struct RouteForecast: Sendable, Hashable, Identifiable {
    public var typeID: String
    /// Departures per day on each leg.
    public var frequency: Double
    public var aircraftNeeded: Int
    public var passengersPerDay: Double
    public var cargoKgPerDay: Double
    /// Passengers carried as a share of seats flown.
    public var loadFactor: Double
    public var revenuePerDay: Double
    public var costPerDay: Double
    public var profitPerDay: Double
    /// Price of the aircraft needed, bought used.
    public var investment: Int
    /// Years to earn back the investment; nil if the route loses money.
    public var paybackYears: Double?
    /// Why this aircraft cannot fly the route (nil if it can).
    public var problem: WorldError?

    public var id: String { typeID }
    public var isViable: Bool { problem == nil && profitPerDay > 0 }
}

extension World {
    /// What a mature route through `stops` flown by `type` earns per day. Leave `frequency` nil to take the schedule the market supports
    /// (and as many aircraft as it needs), or pass the frequency and the number of aircraft to forecast a route as it is set up.
    public func forecast(stops: [String], type: AircraftType, frequency: Double? = nil, fareMultiplier: Double = 1.0, carriesCargo: Bool = true,
                         aircraftCount: Int? = nil) -> RouteForecast {
        var empty = RouteForecast(typeID: type.id, frequency: 0, aircraftNeeded: 0, passengersPerDay: 0, cargoKgPerDay: 0, loadFactor: 0, revenuePerDay: 0, costPerDay: 0,
                                  profitPerDay: 0, investment: 0, paybackYears: nil, problem: nil)
        guard stops.count >= 2, let legs = makeLegs(stops: stops) else {
            empty.problem = .routeNeedsTwoStops
            return empty
        }
        let route = Route(id: 0, name: "", stops: stops, fareMultiplier: min(Route.maxFare, max(Route.minFare, fareMultiplier)), carriesCargo: carriesCargo, frequency: 1,
                          autoFrequency: false, legs: legs, aircraftIDs: [], openedDay: clock.dayIndex, flights: 0, revenueThisMonth: 0, costThisMonth: 0,
                          revenueLastMonth: 0, costLastMonth: 0)
        if let problem = fitProblem(type: type, route: route) {
            empty.problem = problem
            return empty
        }
        return forecast(on: route, type: type, frequency: frequency, aircraftCount: aircraftCount)
    }

    /// The same for a route that exists, using its own schedule and fare, with `aircraftCount` aircraft of this type on it.
    public func forecast(route: Route, type: AircraftType, aircraftCount: Int) -> RouteForecast {
        if let problem = fitProblem(type: type, route: route) {
            return RouteForecast(typeID: type.id, frequency: route.frequency, aircraftNeeded: aircraftCount, passengersPerDay: 0, cargoKgPerDay: 0, loadFactor: 0,
                                 revenuePerDay: 0, costPerDay: 0, profitPerDay: 0, investment: 0, paybackYears: nil, problem: problem)
        }
        return forecast(on: route, type: type, frequency: route.frequency, aircraftCount: aircraftCount)
    }

    func forecast(on route: Route, type: AircraftType, frequency: Double?, aircraftCount: Int?) -> RouteForecast {
        let perAircraft = max(0.05, cyclesPerAircraftPerDay(route: route, type: type))
        var f: Double
        var count: Int
        if let aircraftCount {
            count = max(1, aircraftCount)
            f = min(frequency ?? suggestedFrequency(route: route, type: type, aircraftCount: count), perAircraft * Double(count))
        } else {
            f = frequency ?? Route.snapFrequency(min(demandFrequency(route: route, type: type), Route.maxFrequency))
            count = max(1, Int((f / perAircraft).rounded(.up)))
        }
        f = max(Route.minFrequency, f)

        // Everyone who turns up between two departures boards unless the seats run out; only the people left behind lose patience, and the seat
        // limit already caps them, so the forecast is the smaller of demand and seats.
        let wear = Valuation.wearFactor(ageYears: 12, condition: 80)
        var passengers = 0.0, cargo = 0.0, revenue = 0.0, cost = 0.0, seats = 0.0
        for leg in route.legs {
            guard let a = AirportCatalog.airport(leg.from), let b = AirportCatalog.airport(leg.to) else { continue }
            var mature = leg
            mature.maturity = 1.0
            mature.departuresLastWeek = max(1, Int((f * 7).rounded()))
            let share = capture(route: route, leg: mature, from: a, to: b)
            let carriedPax = min(leg.marketPaxPerDay * share, f * Double(type.seats) * Tuning.loadFactorCap)
            let carriedCargo = route.carriesCargo ? min(leg.marketCargoKgPerDay * share, f * Double(type.cargoKg) * Tuning.cargoLoadLimit) : 0
            let fare = leg.marketFare * route.fareMultiplier
            revenue += carriedPax * fare * (1.0 - Tuning.salesShare) + carriedCargo * Fares.cargoRate(distanceKm: leg.distanceKm)
            let flight = LegEconomics.cost(type: type, from: a, to: b, distanceKm: leg.distanceKm, fuelIndex: market.fuelIndex, wearFactor: wear).total
            cost += f * flight + carriedPax * LegEconomics.perPassenger(from: a, to: b) + carriedCargo * Tuning.cargoHandlingPerKg
            passengers += carriedPax
            cargo += carriedCargo
            seats += f * Double(type.seats)
        }
        cost += Double(count) * LegEconomics.fixedPerDay(type: type)
        let profit = revenue - cost

        let age = type.inProduction ? 12.0 : 35.0
        let investment = count * Valuation.value(type: type, ageYears: age, condition: 80)
        return RouteForecast(typeID: type.id, frequency: f, aircraftNeeded: count, passengersPerDay: passengers, cargoKgPerDay: cargo,
                             loadFactor: seats > 0 ? passengers / seats : 0, revenuePerDay: revenue, costPerDay: cost, profitPerDay: profit, investment: investment,
                             paybackYears: profit > 0 ? Double(investment) / (profit * 365.0) : nil, problem: nil)
    }

    /// The aircraft the airline may operate that could fly this route, best first (quickest payback), only those that make money.
    public func rankedForecasts(stops: [String], limit: Int = 4) -> [RouteForecast] {
        let usable = AircraftCatalog.available(atLevel: airline.level)
        let all = usable.map { forecast(stops: stops, type: $0) }.filter { $0.isViable }
        let ordered = all.sorted { a, b in
            switch (a.paybackYears, b.paybackYears) {
            case let (x?, y?): return x != y ? x < y : a.typeID < b.typeID
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.typeID < b.typeID
            }
        }
        return Array(ordered.prefix(limit))
    }
}
