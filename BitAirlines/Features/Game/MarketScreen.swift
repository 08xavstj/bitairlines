import SwiftUI
import CoreCatalog
import CoreWorld

/// The hangar: used aircraft for sale, and new ones to order.
struct MarketScreen: View {
    let session: GameSession
    @State private var tab = 0
    @State private var filter = MarketFilter()

    var body: some View {
        let world = session.world
        // Every type's fit is worked out once per screen update, not once per card, filter and count.
        let fits = MarketScreen.fitTable(world)
        let used = usedListings(world, fits: fits)
        let new = newTypes(fits: fits)
        Page {
            ScreenHeader(title: "Hangar") { Text("Cash \(Format.compactMoney(world.airline.cash))").pixelFont(10.667).foregroundStyle(Theme.textMuted) }
            PixelChoice(options: [(label: "Used", value: 0), (label: "New", value: 1)], selection: $tab)
            MarketFilterBar(filter: $filter)
            if tab == 0 {
                Text("Used aircraft are ferried to your home airport within a day. The listings change every week.").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                RewardButton(session: session, kind: .brokersTip)
                ForEach(used) { listing in
                    if let type = AircraftCatalog.type(listing.typeID), let fit = fits[type.id] {
                        UsedCard(session: session, listing: listing, type: type, fit: fit)
                    }
                }
            } else {
                Text("New aircraft cost more and take a little longer to arrive, but they are in perfect condition.").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                ForEach(new) { type in
                    if let fit = fits[type.id] { NewCard(session: session, type: type, fit: fit) }
                }
            }
            if (tab == 0 && used.isEmpty) || (tab == 1 && new.isEmpty) {
                Text("Nothing for sale matches. Clear the search or pick another level.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            }
        }
    }

    /// How every aircraft type fits the airline's airports.
    static func fitTable(_ world: World) -> [String: AircraftFit] {
        var table: [String: AircraftFit] = [:]
        for type in AircraftCatalog.all { table[type.id] = world.fit(of: type) }
        return table
    }

    private func shows(_ type: AircraftType, fits: [String: AircraftFit]) -> Bool {
        guard let fit = fits[type.id] else { return false }
        return filter.matches(type, fit: fit)
    }

    /// The listings that match the filter, rare finds first.
    private func usedListings(_ world: World, fits: [String: AircraftFit]) -> [UsedListing] {
        let shown = world.market.listings.filter { AircraftCatalog.type($0.typeID).map { shows($0, fits: fits) } ?? false }
        return shown.filter { $0.rare != nil } + shown.filter { $0.rare == nil }
    }

    private func newTypes(fits: [String: AircraftFit]) -> [AircraftType] {
        AircraftCatalog.all.filter { $0.inProduction && shows($0, fits: fits) }.sorted { ($0.level, $0.priceUSD) < ($1.level, $1.priceUSD) }
    }
}

struct SpecLine: View {
    let type: AircraftType
    var body: some View {
        Text("\(type.seats) seats  \(Format.number(type.cargoKg)) kg freight  \(Format.number(type.rangeKm)) km  \(Format.number(type.cruiseKph)) km/h  \(type.water ? "water only" : "runway " + Format.number(type.runwayFt) + " ft")")
            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
    }
}

struct UsedCard: View {
    let session: GameSession
    let listing: UsedListing
    let type: AircraftType
    let fit: AircraftFit

    var body: some View {
        let world = session.world
        let locked = type.level > world.airline.level
        // A heritage find is shown in the paint it arrives in.
        let paint = listing.rare == .heritage ? RareFinds.heritageLivery(logo: world.airline.branding.logo).branding : world.airline.branding
        Card {
            HStack(spacing: 12) {
                AircraftSpriteView(family: type.family, branding: paint, pixel: 2).frame(width: 130)
                VStack(alignment: .leading, spacing: 3) {
                    if let rare = listing.rare {
                        Tag(text: "Rare find", color: Theme.gold)
                        Text(Words.explain(rare)).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        RewardButton(session: session, kind: .holdRareFind, target: listing.id)
                    }
                    Text(type.displayName.uppercased()).pixelFont(13.333).foregroundStyle(locked ? Theme.textMuted : Theme.textPrimary).lineLimit(1)
                    SpecLine(type: type)
                    Text("\(Int(listing.ageYears)) years old, condition \(Int(listing.condition))%, arrives in \(Format.wait(minutes: Valuation.usedDeliveryMinutes(listing)))").pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                    if listing.rare == .barnFind {
                        let cost = Restorations.cost(type: type, ageYears: listing.ageYears)
                        let days = Restorations.days(ageYears: listing.ageYears, fasterHangar: false)
                        Text("It cannot fly until restored: about \(Format.compactMoney(cost)) and \(days) days in the hangar (half that with a hangar). Then it is near new, in the heritage livery.")
                            .pixelFont(10.667).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
                    }
                    FitSummary(fit: fit)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(Format.dollars(listing.price)).pixelFont(13.333).foregroundStyle(world.airline.cash >= listing.price ? Theme.good : Theme.bad)
                    if locked {
                        Tag(text: "Level \(type.level)", color: Theme.bad)
                    } else {
                        Button("Buy") { session.perform(sound: .coin) { _ = try $0.buyUsed(listingID: listing.id) } }.buttonStyle(.smallProminent).disabled(world.airline.cash < listing.price)
                    }
                }
            }
        }
    }
}

struct NewCard: View {
    let session: GameSession
    let type: AircraftType
    let fit: AircraftFit

    var body: some View {
        let world = session.world
        let locked = type.level > world.airline.level
        Card {
            HStack(spacing: 12) {
                AircraftSpriteView(family: type.family, branding: world.airline.branding, pixel: 2).frame(width: 130)
                VStack(alignment: .leading, spacing: 3) {
                    Text(type.displayName.uppercased()).pixelFont(13.333).foregroundStyle(locked ? Theme.textMuted : Theme.textPrimary).lineLimit(1)
                    SpecLine(type: type)
                    Text("Arrives in about \(Format.wait(minutes: Valuation.newDeliveryMinutes(level: type.level)))").pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                    FitSummary(fit: fit)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(Format.compactMoney(type.priceUSD)).pixelFont(13.333).foregroundStyle(world.airline.cash >= type.priceUSD ? Theme.good : Theme.bad)
                    if locked {
                        Tag(text: "Level \(type.level)", color: Theme.bad)
                    } else {
                        Button("Order") { session.perform(sound: .coin) { _ = try $0.orderNew(typeID: type.id) } }.buttonStyle(.smallProminent).disabled(world.airline.cash < type.priceUSD)
                    }
                }
            }
        }
    }
}
