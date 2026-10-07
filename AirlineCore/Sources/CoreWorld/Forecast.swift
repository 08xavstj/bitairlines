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
    /// The heavy checks spread over the days (already in `costPerDay`).
    public var heavyCheckPerDay: Double = 0
    /// Daily slots the airline would have to buy at busy stops before the route can fly (SlotNeeds.swift), counted in the investment.
    public var slotCost: Int = 0

    public var id: String { typeID }
    public var isViable: Bool { problem == nil && profitPerDay > 0 }
}

extension Tuning {
    /// The used aircraft a forecast assumes when the airline has none of the type: about the age and condition the hangar sells
    /// (types still built are a few years old; the others are old timers).
    public static let forecastAgeInProduction = 12.0
    public static let forecastConditionInProduction = 80.0
    public static let forecastAgeOutOfProduction = 50.0
    public static let forecastConditionOutOfProduction = 50.0
}

/// How worn the aircraft a forecast stands for are: the maintenance multiplier and the heavy-check bill, on average.
struct ForecastWear: Sendable {
    var maintenance: Double
    var checkCost: Double
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
        var result = forecast(on: route, type: type, frequency: frequency, aircraftCount: aircraftCount)
        // An open route already counts in slotsScheduled; a new one must still buy its slots.
        let slots = slotCost(stops: stops, frequency: result.frequency)
        if slots > 0 {
            result.slotCost = slots
            result.investment += slots
            result.paybackYears = result.profitPerDay > 0 ? Double(result.investment) / (result.profitPerDay * 365.0) : nil
        }
        return result
    }

    /// The same for a route that exists, using its own fare and (unless `suggestedSchedule`) its own schedule, with `aircraftCount` aircraft of this type on it.
    /// `suggestedSchedule` is for an aircraft about to be assigned to a route that picks its own schedule.
    public func forecast(route: Route, type: AircraftType, aircraftCount: Int, suggestedSchedule: Bool = false) -> RouteForecast {
        if let problem = fitProblem(type: type, route: route) {
            return RouteForecast(typeID: type.id, frequency: route.frequency, aircraftNeeded: aircraftCount, passengersPerDay: 0, cargoKgPerDay: 0, loadFactor: 0,
                                 revenuePerDay: 0, costPerDay: 0, profitPerDay: 0, investment: 0, paybackYears: nil, problem: problem)
        }
        return forecast(on: route, type: type, frequency: suggestedSchedule ? nil : route.frequency, aircraftCount: aircraftCount)
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
        let worn = forecastWear(type: type, route: route)
        let wear = worn.maintenance
        var passengers = 0.0, cargo = 0.0, revenue = 0.0, cost = 0.0, seats = 0.0, blockHours = 0.0
        for leg in route.legs {
            guard let a = AirportCatalog.airport(leg.from), let b = AirportCatalog.airport(leg.to) else { continue }
            var mature = leg
            mature.maturity = 1.0
            mature.departuresLastWeek = max(1, Int((f * 7).rounded()))
            let share = capture(route: route, leg: mature, from: a, to: b)
            // Only so many people (and so much freight) wait at a gate at once, which caps what a sparse schedule can ever carry.
            let paxPerDay = (leg.marketPaxPerDay + leg.connectingPaxPerDay) * share
            let cargoPerDay = leg.marketCargoKgPerDay * share / max(0.01, fareFactor(route: route, leg: mature))
            let carriedPax = min(paxPerDay, f * (2.0 * paxPerDay + 4.0), f * Double(type.seats) * Tuning.loadFactorCap)
            let carriedCargo = route.carriesCargo ? min(cargoPerDay, f * (2.0 * cargoPerDay + 40.0), f * Double(type.cargoKg) * Tuning.cargoLoadLimit) : 0
            let fare = leg.blendedFare * route.fareMultiplier
            revenue += carriedPax * fare * (1.0 - Tuning.salesShare) + carriedCargo * Fares.cargoRate(distanceKm: leg.distanceKm) * cargoRateFactor
            let flight = LegEconomics.cost(type: type, from: a, to: b, distanceKm: leg.distanceKm, fuelIndex: fuelIndex(leaving: a.code),
                                           wearFactor: wear * maintenanceFactor, adjust: costAdjust)
            cost += f * flight.total + carriedPax * passengerCost(from: a, to: b, service: route.service) + carriedCargo * Tuning.cargoHandlingPerKg
            blockHours += f * flight.blockHours
            passengers += carriedPax
            cargo += carriedCargo
            seats += f * Double(type.seats)
        }
        let pilotPay = Double(World.pilotsNeeded(type) * salary(for: RatingGroup.of(type.family))) * 12.0 / 365.0
        cost += Double(count) * (LegEconomics.fixedPerDay(type: type) + pilotPay)
        // Heavy checks, spread over the days: each aircraft's bill over the calendar interval or the hours it flies, whichever comes first.
        let checks = Double(count) * heavyCheckPerDay(checkCost: worn.checkCost, blockHoursPerDay: blockHours / Double(count))
        cost += checks
        let profit = revenue - cost

        let used = World.forecastAgeAndCondition(type)
        let investment = count * Valuation.value(type: type, ageYears: used.age, condition: used.condition)
        return RouteForecast(typeID: type.id, frequency: f, aircraftNeeded: count, passengersPerDay: passengers, cargoKgPerDay: cargo,
                             loadFactor: seats > 0 ? passengers / seats : 0, revenuePerDay: revenue, costPerDay: cost, profitPerDay: profit, investment: investment,
                             paybackYears: profit > 0 ? Double(investment) / (profit * 365.0) : nil, problem: nil, heavyCheckPerDay: checks)
    }

    /// The age and condition of the used aircraft a forecast assumes for a type the airline does not have (and prices its purchase at).
    static func forecastAgeAndCondition(_ type: AircraftType) -> (age: Double, condition: Double) {
        type.inProduction ? (Tuning.forecastAgeInProduction, Tuning.forecastConditionInProduction)
            : (Tuning.forecastAgeOutOfProduction, Tuning.forecastConditionOutOfProduction)
    }

    /// The wear a forecast uses: the airline's own aircraft of the type on the route, else in the fleet, else a typical used one,
    /// so an old starter or an old timer from the hangar is not promised the maintenance bill of a young aircraft.
    func forecastWear(type: AircraftType, route: Route) -> ForecastWear {
        let ofType = aircraft.filter { $0.typeID == type.id }
        let onRoute = ofType.filter { route.aircraftIDs.contains($0.id) }
        let planes = onRoute.isEmpty ? ofType : onRoute
        guard !planes.isEmpty else {
            let used = World.forecastAgeAndCondition(type)
            return ForecastWear(maintenance: Valuation.wearFactor(ageYears: used.age, condition: used.condition),
                                checkCost: Double(heavyCheckCost(type: type, ageYears: used.age)))
        }
        var maintenance = 0.0, checkCost = 0.0
        for plane in planes {
            let age = plane.ageYears(atDay: clock.dayIndex)
            maintenance += Valuation.wearFactor(ageYears: age, condition: plane.condition)
            checkCost += Double(heavyCheckCost(type: type, ageYears: age))
        }
        let n = Double(planes.count)
        return ForecastWear(maintenance: maintenance / n, checkCost: checkCost / n)
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
