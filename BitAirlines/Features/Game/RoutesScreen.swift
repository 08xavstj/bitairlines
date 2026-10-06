import SwiftUI
import CoreCatalog
import CoreWorld

/// A value with minus and plus buttons that steps through a fixed list of allowed values.
struct ListStepper: View {
    let label: String
    let values: [Double]
    let current: Double
    var display: (Double) -> String
    let onChange: (Double) -> Void

    var body: some View {
        let index = values.enumerated().min { abs($0.element - current) < abs($1.element - current) }?.offset ?? 0
        HStack(spacing: 10) {
            Text(label).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            PixelSquareButton(icon: .minus, label: "Decrease \(label)") { onChange(values[max(0, index - 1)]) }.disabled(index <= 0)
            Text(display(values[index])).pixelFont(13.333).foregroundStyle(Theme.textPrimary).lineLimit(1).fixedSize().frame(minWidth: 70)
            PixelSquareButton(icon: .plus, label: "Increase \(label)") { onChange(values[min(values.count - 1, index + 1)]) }.disabled(index >= values.count - 1)
        }
    }
}

enum RouteSteps {
    static let frequencies: [Double] = [0.25, 0.5, 1, 1.5, 2, 3, 4, 5, 6, 8, 10, 12, 16, 24]
    static let fares: [Double] = stride(from: 50, through: 200, by: 5).map { Double($0) / 100 }

    static func frequencyText(_ f: Double) -> String {
        if f < 1 { return f == 0.25 ? "1 per 4 days" : "1 per 2 days" }
        return f == f.rounded() ? "\(Int(f)) per day" : "\(Format.oneDecimal(f)) per day"
    }
}

struct RoutesScreen: View {
    let session: GameSession
    @State private var deleting: Int?
    @State private var selling: Int?

    var body: some View {
        let world = session.world
        Page {
            ScreenHeader(title: "Routes") { Text("\(world.routes.count) routes").pixelFont(10.667).foregroundStyle(Theme.textMuted) }
            RouteIdeasCard(session: session)
            if world.routes.isEmpty {
                Card { Text("No routes yet. Open one of the suggested routes above, or go to the Map, tap New route and tap the airports in the order you want to fly them. Then assign an aircraft from Fleet.").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true) }
            }
            ForEach(world.routes) { route in RouteCard(session: session, route: route, onDelete: { deleting = route.id }, onSell: { selling = route.id }) }
        }
        .pixelConfirm("Close this route?", message: "Its aircraft are parked. Money already earned is kept.", confirm: "Close route", destructive: true,
                      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            if let id = deleting { session.perform { try $0.deleteRoute(id: id) } }
            deleting = nil
        }
        .pixelConfirm("Sell this route?", message: GrowthWords.sellRoute(price: selling.map { world.routeSalePrice(routeID: $0) } ?? 0), confirm: "Sell route", destructive: true,
                      isPresented: Binding(get: { selling != nil }, set: { if !$0 { selling = nil } })) {
            if let id = selling { session.perform(sound: .coin) { _ = try $0.sellRoute(routeID: id) } }
            selling = nil
        }
    }
}

struct RouteCard: View {
    let session: GameSession
    let route: Route
    let onDelete: () -> Void
    var onSell: (() -> Void)? = nil

    var body: some View {
        let world = session.world
        let planes = route.aircraftIDs.compactMap { id in world.aircraft.first { $0.id == id } }
        let types = planes.compactMap { $0.type }
        let cycleHours = cycle(route: route, type: types.first)
        let needed = max(1, Int((route.frequency * cycleHours / 24).rounded(.up)))
        let first = route.legs.first
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(route.name).pixelFont(16).foregroundStyle(Theme.accent).fixedSize(horizontal: false, vertical: true)
                        Tag(text: "\(planes.count) aircraft", color: planes.isEmpty ? Theme.bad : Theme.good)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 6) {
                        Button("Close route") { onDelete() }.buttonStyle(.smallDanger)
                        if let onSell { Button("Sell route") { onSell() }.buttonStyle(.small) }
                    }
                }
                RouteProfitLine(route: route)
                ListStepper(label: "Flights", values: RouteSteps.frequencies, current: route.frequency, display: RouteSteps.frequencyText) { v in
                    session.perform { try $0.setFrequency(routeID: route.id, perDay: v) }
                }
                if !route.autoFrequency && !planes.isEmpty {
                    Button("Use the suggested schedule") { session.perform { try $0.applySuggestedFrequency(routeID: route.id) } }.buttonStyle(.small)
                }
                ListStepper(label: "Fare", values: RouteSteps.fares, current: route.fareMultiplier, display: { fareText($0, first: first) }) { v in
                    session.perform { try $0.setFare(routeID: route.id, multiplier: v) }
                }
                FareOutlook(world: world, route: route)
                Toggle(isOn: Binding(get: { route.carriesCargo }, set: { v in session.perform { try $0.setCargo(routeID: route.id, enabled: v) } })) {
                    Text("Carry freight").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                }.toggleStyle(PixelToggleStyle())
                ServicePicker(session: session, route: route)
                RouteNotes(world: world, route: route)

                if planes.isEmpty {
                    Text("No aircraft yet. Assign one from Fleet.").pixelFont(10.667).foregroundStyle(Theme.bad)
                } else {
                    Text("Aircraft: " + planes.map { $0.registration }.joined(separator: ", ")).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    if planes.count < needed {
                        Text("This schedule needs about \(needed) aircraft. With \(planes.count) some departures will be missed.").pixelFont(10.667).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
                    } else if planes.count > needed {
                        Text("About \(needed) aircraft are enough for this schedule. The rest sit idle.").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                RouteOutlook(world: world, route: route)
                KeyValueRow("This month", Format.signedMoney(route.revenueThisMonth - route.costThisMonth), color: route.revenueThisMonth >= route.costThisMonth ? Theme.good : Theme.bad)
                KeyValueRow("Last month", Format.signedMoney(route.revenueLastMonth - route.costLastMonth), color: route.revenueLastMonth >= route.costLastMonth ? Theme.good : Theme.bad)
                ForEach(Array(route.legs.enumerated()), id: \.offset) { _, leg in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(Place.name(leg.from)) to \(Place.name(leg.to)), \(Format.km(leg.distanceKm))")
                            .pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        Text("Market \(Format.oneDecimal(leg.marketPaxPerDay)) people and \(Format.number(Int(leg.marketCargoKgPerDay))) kg a day. Carried \(Format.number(leg.passengersCarried)) so far.")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        StatBar(label: "Awareness", value: leg.maturity * 100, color: Theme.info, valueText: Format.percent(leg.maturity))
                    }
                }
            }
        }
    }

    private func fareText(_ multiplier: Double, first: LegState?) -> String {
        let fare = Int(((first?.marketFare ?? 0) * multiplier).rounded())
        return "\(Int((multiplier * 100).rounded()))% ($\(fare))"
    }

    /// Hours for one aircraft to fly the whole cycle, with turnarounds.
    private func cycle(route: Route, type: AircraftType?) -> Double {
        guard let type else { return 0 }
        return route.legs.reduce(0.0) { $0 + type.blockHours(km: $1.distanceKm) + Tuning.turnaroundHours(type.engine) }
    }
}
