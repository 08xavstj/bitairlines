import SwiftUI
import CoreWorld

/// The fuel market: today's price, the last few months as a chart, and buying fuel ahead.
struct FuelCard: View {
    let session: GameSession

    var body: some View {
        let world = session.world
        let stock = world.ops.fuel
        let capacity = world.fuelCapacityKg
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text("FUEL").pixelFont(13.333).foregroundStyle(Theme.accent)
                    Spacer(minLength: 12)
                    Text("\(Int((world.market.fuelIndex * 100).rounded()))% of normal today").pixelFont(10.667).foregroundStyle(world.market.fuelIndex > 1.1 ? Theme.bad : Theme.good)
                }
                FuelChart(history: world.ops.fuelHistory).frame(height: 60)
                KeyValueRow("In your tanks", "\(Format.number(Int(stock.kg))) of \(Format.number(Int(capacity))) kg" + (stock.kg > 0 ? ", bought at \(Int((stock.priceIndex * 100).rounded()))%" : ""))
                // Side by side when they fit, one above the other when they do not (narrow screen or large text).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { buyButtons(world) }
                    VStack(alignment: .leading, spacing: 8) { buyButtons(world) }
                }
                if stock.kg + 5_000 > capacity {
                    Text("Your tanks are too full to buy more right now.").pixelFont(10.667).foregroundStyle(Theme.gold)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Fuel bought ahead is used first, at the price you paid. It counts as invested until it is burned, then as a flight cost. Buy when it is cheap. Fuel depots at your bases hold more.")
                    .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func buyButtons(_ world: World) -> some View {
        ForEach([5_000.0, 20_000.0], id: \.self) { kg in
            Button { session.perform(sound: .coin) { try $0.buyFuel(kg: kg) } } label: {
                HangarButtonText("Buy \(Format.number(Int(kg))) kg for \(Format.compactMoney(world.fuelPrice(kg: kg)))")
            }
            .buttonStyle(.small).disabled(world.ops.fuel.kg + kg > world.fuelCapacityKg)
        }
    }
}

/// The fuel price over the last few months, as blocks around the 100% line.
struct FuelChart: View {
    let history: [Double]

    var body: some View {
        Canvas { context, size in
            let low = 0.5, high = 2.0
            func y(_ v: Double) -> CGFloat { size.height * CGFloat(1 - (min(high, max(low, v)) - low) / (high - low)) }
            context.fill(Path(CGRect(x: 0, y: y(1.0), width: size.width, height: 1)), with: .color(Theme.panelBorder), style: FillStyle(antialiased: false))
            guard !history.isEmpty else { return }
            let slot = size.width / CGFloat(World.fuelHistoryDays)
            for (i, v) in history.enumerated() {
                let top = y(v)
                context.fill(Path(CGRect(x: CGFloat(i) * slot, y: top, width: max(1, slot), height: 3)), with: .color(v > 1.1 ? Theme.bad : (v < 0.95 ? Theme.good : Theme.gold)),
                             style: FillStyle(antialiased: false))
            }
        }
        .accessibilityLabel("Fuel price over the last \(history.count) days")
    }
}
