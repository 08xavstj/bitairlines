import SwiftUI
import CoreCatalog
import CoreWorld

/// The aircraft that would pay on a route being planned, best first, with what it costs and how long it takes to earn that back.
struct ForecastList: View {
    let session: GameSession
    let stops: [String]
    @State private var ranked: [RouteForecast] = []

    var body: some View {
        let cash = session.world.airline.cash
        VStack(alignment: .leading, spacing: 4) {
            Text("BEST AIRCRAFT FOR IT").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            if ranked.isEmpty {
                Text("No aircraft you can fly would make money on this route.").pixelFont(10.667).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(ranked) { forecast in ForecastRow(forecast: forecast, canAfford: forecast.investment <= cash) }
        }
        .onChange(of: stops, initial: true) { _, now in ranked = now.count >= 2 ? session.world.rankedForecasts(stops: now, limit: 3) : [] }
    }
}

struct ForecastRow: View {
    let forecast: RouteForecast
    let canAfford: Bool

    var body: some View {
        let name = AircraftCatalog.type(forecast.typeID)?.name ?? forecast.typeID
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(forecast.aircraftNeeded > 1 ? "\(name) x\(forecast.aircraftNeeded)" : name).pixelFont(10.667).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 4)
                Text(Format.perDay(forecast.profitPerDay)).pixelFont(10.667).foregroundStyle(Theme.good).lineLimit(1).fixedSize()
            }
            Text("About \(Format.compactMoney(forecast.investment)) to buy, back in \(Format.payback(years: forecast.paybackYears))" + (canAfford ? "" : ". Not enough cash yet."))
                .pixelFont(10.667).foregroundStyle(canAfford ? Theme.textMuted : Theme.gold).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// On a route card: what the route should earn with the aircraft on it now, next to what it earned last month.
struct RouteOutlook: View {
    let world: World
    let route: Route

    var body: some View {
        let planes = route.aircraftIDs.compactMap { id in world.aircraft.first { $0.id == id } }
        if let type = planes.first?.type, route.aircraftIDs.count > 0 {
            let forecast = world.forecast(route: route, type: type, aircraftCount: planes.count)
            if forecast.problem == nil {
                KeyValueRow("Expected", Format.perDay(forecast.profitPerDay), color: forecast.profitPerDay >= 0 ? Theme.good : Theme.bad)
                Text("Once people know the route, at this schedule and fare, with \(planes.count) \(type.displayName). Carries about \(Int(forecast.passengersPerDay.rounded())) people and \(Format.number(Int(forecast.cargoKgPerDay.rounded()))) kg a day.")
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
