import SwiftUI
import CoreCatalog
import CoreWorld

/// In the aircraft sheet: trade this aircraft in for a bigger one. The dealer's price for it counts towards the new one.
struct TradeInButton: View {
    let session: GameSession
    let plane: Aircraft
    @State private var showing = false

    var body: some View {
        let problem = session.world.tradeInProblem(aircraftID: plane.id)
        // The Sell card says why above both buttons (FleetText.sellBlock: the same checks); say it here too when that line is empty.
        let unexplained = problem != nil && FleetText.sellBlock(plane) == nil
        VStack(alignment: .leading, spacing: 4) {
            Button { showing = true } label: { HangarButtonText("Trade in") }
                .buttonStyle(.small)
                .disabled(problem != nil)
                .accessibilityHint(problem.map { FleetText.sellBlock(plane) ?? Messages.describe($0) } ?? "Trade it in towards a bigger aircraft.")
            if unexplained, let problem {
                Text(Messages.describe(problem)).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showing) { TradeInSheet(session: session, aircraftID: plane.id) }
    }
}

/// Bigger aircraft the airline may buy now, used from the hangar or new, with what is left to pay after the trade-in.
struct TradeInSheet: View {
    let session: GameSession
    let aircraftID: Int
    @Environment(\.dismiss) private var dismiss

    /// How many offers of each kind are shown.
    private let shown = 8

    var body: some View {
        let world = session.world
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(title: "Trade in") { Button { dismiss() } label: { HangarButtonText("Close") }.buttonStyle(.small) }
            HangarNotice(session: session)
            if let plane = world.aircraft.first(where: { $0.id == aircraftID }), let type = plane.type {
                let value = world.saleValue(of: plane)
                let used = usedOffers(world, seats: type.seats, typeID: type.id)
                let newTypes = newOffers(world, seats: type.seats, typeID: type.id)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(plane.registration) counts for \(Format.dollars(value)) towards a bigger aircraft. You have \(Format.dollars(world.airline.cash)).")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        if used.isEmpty && newTypes.isEmpty { EmptyNote("Nothing bigger you may fly is for sale right now.") }
                        if !used.isEmpty { SectionTitle("Used, in the hangar") }
                        ForEach(used) { listing in
                            TradeInRow(name: AircraftCatalog.type(listing.typeID)?.displayName ?? listing.typeID,
                                       detail: "\(Int(listing.ageYears.rounded())) years old, \(Int(listing.condition))% condition",
                                       price: listing.price, value: value, cash: world.airline.cash) {
                                trade { try $0.tradeIn(aircraftID: aircraftID, forListing: listing.id) }
                            }
                        }
                        if !newTypes.isEmpty { SectionTitle("New from the factory") }
                        ForEach(newTypes) { offer in
                            TradeInRow(name: offer.displayName, detail: "\(offer.seats) seats, new", price: offer.priceUSD, value: value, cash: world.airline.cash) {
                                trade { try $0.tradeIn(aircraftID: aircraftID, forNewType: offer.id) }
                            }
                        }
                    }
                }
            } else {
                EmptyNote("This aircraft is gone.")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .screenBackground()
        .onAppear { session.notice = nil }
    }

    private func trade(_ change: (inout World) throws -> Int) {
        if session.perform(sound: .coin, { _ = try change(&$0) }) { dismiss() }
    }

    /// Used aircraft at least as big as this one that the airline may fly and that can be delivered (the check buyUsed makes),
    /// cheapest first.
    private func usedOffers(_ world: World, seats: Int, typeID: String) -> [UsedListing] {
        let fits = world.market.listings.filter { listing in
            guard let t = AircraftCatalog.type(listing.typeID) else { return false }
            return t.id != typeID && t.seats >= seats && t.level <= world.airline.level && world.deliveryProblem(t) == nil
        }
        return Array(fits.sorted { $0.price != $1.price ? $0.price < $1.price : $0.id < $1.id }.prefix(shown))
    }

    /// New types at least as big as this one, in production, that the airline may fly and that can be delivered, cheapest first.
    private func newOffers(_ world: World, seats: Int, typeID: String) -> [AircraftType] {
        let fits = AircraftCatalog.available(atLevel: world.airline.level).filter { t in
            t.inProduction && t.id != typeID && t.seats >= seats && world.deliveryProblem(t) == nil
        }
        return Array(fits.sorted { $0.priceUSD != $1.priceUSD ? $0.priceUSD < $1.priceUSD : $0.id < $1.id }.prefix(shown))
    }
}

/// One aircraft on offer, with the price after the trade-in and the button.
struct TradeInRow: View {
    let name: String
    let detail: String
    let price: Int
    let value: Int
    let cash: Int
    let action: () -> Void

    var body: some View {
        let toPay = max(0, price - value)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name.uppercased()).pixelFont(13.333).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(detail).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                Text("\(Format.dollars(price)), you pay \(Format.dollars(toPay)) after the trade-in.")
                    .pixelFont(10.667).foregroundStyle(cash >= toPay ? Theme.good : Theme.bad).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { action() } label: { HangarButtonText("Trade in") }
                .buttonStyle(.smallProminent)
                .disabled(cash < toPay)
        }
        .padding(12).background(PixelPanel())
    }
}
