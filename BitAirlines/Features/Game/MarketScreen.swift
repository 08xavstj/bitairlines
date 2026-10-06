import SwiftUI
import CoreCatalog
import CoreWorld

/// The hangar: used aircraft for sale, and new ones to order.
struct MarketScreen: View {
    let session: GameSession
    @State private var tab = 0

    var body: some View {
        let world = session.world
        Page {
            ScreenHeader(title: "Hangar") { Text("Cash \(Format.compactMoney(world.airline.cash))").pixelFont(10.667).foregroundStyle(Theme.textMuted) }
            PixelChoice(options: [(label: "Used", value: 0), (label: "New", value: 1)], selection: $tab)
            if tab == 0 {
                Text("Used aircraft arrive at your home airport a few days after you buy them. The listings change every week.").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                ForEach(world.market.listings) { listing in
                    if let type = AircraftCatalog.type(listing.typeID) {
                        UsedCard(session: session, listing: listing, type: type)
                    }
                }
            } else {
                Text("New aircraft cost more and take longer to arrive, but they are in perfect condition.").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                ForEach(newTypes) { type in NewCard(session: session, type: type) }
            }
        }
    }

    private var newTypes: [AircraftType] {
        AircraftCatalog.all.filter { $0.inProduction }.sorted { ($0.level, $0.priceUSD) < ($1.level, $1.priceUSD) }
    }
}

struct SpecLine: View {
    let type: AircraftType
    var body: some View {
        Text("\(type.seats) seats  \(Format.number(type.cargoKg)) kg freight  \(Format.number(type.rangeKm)) km  \(Format.number(type.cruiseKph)) km/h  runway \(Format.number(type.runwayFt)) ft")
            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
    }
}

struct UsedCard: View {
    let session: GameSession
    let listing: UsedListing
    let type: AircraftType

    var body: some View {
        let world = session.world
        let locked = type.level > world.airline.level
        Card {
            HStack(spacing: 12) {
                AircraftSpriteView(family: type.family, branding: world.airline.branding, pixel: 2).frame(width: 130)
                VStack(alignment: .leading, spacing: 3) {
                    Text(type.displayName.uppercased()).pixelFont(13.333).foregroundStyle(locked ? Theme.textMuted : Theme.textPrimary).lineLimit(1)
                    SpecLine(type: type)
                    Text("\(Int(listing.ageYears)) years old, condition \(Int(listing.condition))%, arrives in \(listing.deliveryDays) days").pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(Format.dollars(listing.price)).pixelFont(13.333).foregroundStyle(world.airline.cash >= listing.price ? Theme.good : Theme.bad)
                    if locked {
                        Tag(text: "Level \(type.level)", color: Theme.bad)
                    } else {
                        Button("Buy") { session.perform { _ = try $0.buyUsed(listingID: listing.id) } }.buttonStyle(.smallProminent).disabled(world.airline.cash < listing.price)
                    }
                }
            }
        }
    }
}

struct NewCard: View {
    let session: GameSession
    let type: AircraftType

    var body: some View {
        let world = session.world
        let locked = type.level > world.airline.level
        Card {
            HStack(spacing: 12) {
                AircraftSpriteView(family: type.family, branding: world.airline.branding, pixel: 2).frame(width: 130)
                VStack(alignment: .leading, spacing: 3) {
                    Text(type.displayName.uppercased()).pixelFont(13.333).foregroundStyle(locked ? Theme.textMuted : Theme.textPrimary).lineLimit(1)
                    SpecLine(type: type)
                    Text("Arrives in about \(Valuation.newDeliveryDays(level: type.level)) days").pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(Format.compactMoney(type.priceUSD)).pixelFont(13.333).foregroundStyle(world.airline.cash >= type.priceUSD ? Theme.good : Theme.bad)
                    if locked {
                        Tag(text: "Level \(type.level)", color: Theme.bad)
                    } else {
                        Button("Order") { session.perform { _ = try $0.orderNew(typeID: type.id) } }.buttonStyle(.smallProminent).disabled(world.airline.cash < type.priceUSD)
                    }
                }
            }
        }
    }
}
