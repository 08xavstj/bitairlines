import SwiftUI
import CoreCatalog
import CoreWorld

/// On a route being planned: first what the player's own aircraft would earn on it, then the aircraft they could buy that would
/// pay, best first, with what each costs and how long it takes to earn that back.
struct ForecastList: View {
    let session: GameSession
    let stops: [String]
    @State private var own: [OwnForecast] = []
    @State private var ranked: [RouteForecast] = []

    var body: some View {
        let cash = session.world.airline.cash
        VStack(alignment: .leading, spacing: 4) {
            if !own.isEmpty {
                Text("YOUR AIRCRAFT").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                ForEach(own) { item in OwnForecastRow(item: item) }
            }
            Text(own.isEmpty ? "BEST AIRCRAFT FOR IT" : "OTHERS YOU COULD BUY").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            if ranked.isEmpty {
                Text(own.isEmpty ? "No aircraft you can fly would make money on this route." : "No other aircraft you can fly would make money on this route.")
                    .pixelFont(10.667).foregroundStyle(own.isEmpty ? Theme.gold : Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(ranked) { forecast in ForecastRow(forecast: forecast, canAfford: forecast.investment <= cash) }
        }
        .onChange(of: stops, initial: true) { _, now in refresh(now) }
    }

    private func refresh(_ now: [String]) {
        guard now.count >= 2 else { own = []; ranked = []; return }
        let world = session.world
        own = OwnForecast.list(world: world, stops: now)
        let owned = Set(own.map(\.forecast.typeID))
        ranked = Array(world.rankedForecasts(stops: now, limit: 3 + owned.count).filter { !owned.contains($0.typeID) }.prefix(3))
    }
}

/// What one of the player's own aircraft types would earn on a planned route, flown by one aircraft on its own.
struct OwnForecast: Identifiable {
    let registration: String
    let count: Int
    let forecast: RouteForecast
    var id: String { forecast.typeID }

    /// One line per type the airline owns (delivered) that can fly the stops, in fleet order.
    static func list(world: World, stops: [String]) -> [OwnForecast] {
        var seen: [String] = []
        var items: [OwnForecast] = []
        for plane in world.aircraft where plane.isDelivered && !seen.contains(plane.typeID) {
            seen.append(plane.typeID)
            guard let type = plane.type else { continue }
            let forecast = world.forecast(stops: stops, type: type, aircraftCount: 1)
            guard forecast.problem == nil else { continue }
            let count = world.aircraft.filter { $0.isDelivered && $0.typeID == plane.typeID }.count
            items.append(OwnForecast(registration: plane.registration, count: count, forecast: forecast))
        }
        return items
    }
}

struct OwnForecastRow: View {
    let item: OwnForecast

    var body: some View {
        let name = AircraftCatalog.type(item.forecast.typeID)?.name ?? item.forecast.typeID
        let who = item.count > 1 ? "Your \(name), like \(item.registration)" : "Your \(item.registration) (\(name))"
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top, spacing: 6) {
                Text(who).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(Format.perDay(item.forecast.profitPerDay)).pixelFont(10.667)
                    .foregroundStyle(item.forecast.profitPerDay >= 0 ? Theme.good : Theme.bad).lineLimit(1).fixedSize()
            }
            Text("One aircraft, \(RouteSteps.frequencyText(item.forecast.frequency)) each way, about \(Int(item.forecast.passengersPerDay.rounded())) people a day, once people know it.")
                .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ForecastRow: View {
    let forecast: RouteForecast
    let canAfford: Bool

    var body: some View {
        let name = AircraftCatalog.type(forecast.typeID)?.name ?? forecast.typeID
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top, spacing: 6) {
                Text(forecast.aircraftNeeded > 1 ? "\(name) x\(forecast.aircraftNeeded)" : name)
                    .pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(Format.perDay(forecast.profitPerDay)).pixelFont(10.667).foregroundStyle(Theme.good).lineLimit(1).fixedSize()
            }
            Text("About \(Format.compactMoney(forecast.investment)) to buy, back in \(Format.payback(years: forecast.paybackYears))" + (canAfford ? "" : ". Not enough cash yet."))
                .pixelFont(10.667).foregroundStyle(canAfford ? Theme.textMuted : Theme.gold).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// On a route card: what the route should earn with the aircraft on it now, next to what it earned last month.
/// The forecast is cached (see OutlookCache) and only worked out again when the route's settings or aircraft change.
struct RouteOutlook: View {
    let world: World
    let route: Route

    var body: some View {
        let planes = route.aircraftIDs.compactMap { id in world.aircraft.first { $0.id == id } }
        if let type = planes.first?.type, route.aircraftIDs.count > 0 {
            let forecast = OutlookCache.shared.forecast(world: world, route: route, planes: planes, type: type)
            if forecast.problem == nil {
                KeyValueRow("Expected", Format.perDay(forecast.profitPerDay), color: forecast.profitPerDay >= 0 ? Theme.good : Theme.bad)
                Text("Once people know the route, at this schedule and fare, with \(planes.count) \(type.displayName). Carries about \(Int(forecast.passengersPerDay.rounded())) people and \(Format.number(Int(forecast.cargoKgPerDay.rounded()))) kg a day.")
                    .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Under the fare stepper: how full the route should fly and what it should earn at the fare set now, so the player sees the trade-off
/// while stepping the fare. Uses the same cached forecast as RouteOutlook. Shows nothing until an aircraft is on the route.
struct FareOutlook: View {
    let world: World
    let route: Route

    var body: some View {
        let planes = route.aircraftIDs.compactMap { id in world.aircraft.first { $0.id == id } }
        if let type = planes.first?.type {
            let forecast = OutlookCache.shared.forecast(world: world, route: route, planes: planes, type: type)
            if forecast.problem == nil {
                Text("At this fare: about \(Format.percent(forecast.loadFactor)) full, \(Format.perDay(forecast.profitPerDay))")
                    .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// In the aircraft sheet, under a route it could be assigned to: what this aircraft would earn there on its own.
struct AssignOutlook: View {
    let world: World
    let route: Route
    let type: AircraftType

    var body: some View {
        let forecast = world.forecast(route: route, type: type, aircraftCount: 1, suggestedSchedule: route.autoFrequency)
        if forecast.problem == nil {
            Text("On its own: \(Format.perDay(forecast.profitPerDay))").pixelFont(10.667).foregroundStyle(forecast.profitPerDay >= 0 ? Theme.good : Theme.bad)
        }
    }
}
