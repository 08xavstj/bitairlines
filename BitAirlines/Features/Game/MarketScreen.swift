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
        // Every type's fit, kept between clock ticks (FitCache): it changes only when the network, bases or level change.
        let fits = FitCache.shared.table(world)
        let used = usedListings(world, fits: fits)
        let new = newTypes(fits: fits)
        Page(lazy: true) {
            ScreenHeader(title: "Hangar") {
                HStack(spacing: 12) {
                    Text("Cash \(Format.compactMoney(world.airline.cash))").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                    PixelChoice(options: [(label: "Used", value: 0), (label: "New", value: 1)], selection: $tab).frame(width: 200)
                }
            }
            MarketFilterBar(filter: $filter)
            if tab == 0 {
                Text("Used aircraft arrive within a day, at your home airport when they can use it. The listings change every week.").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                RewardButton(session: session, kind: .brokersTip)
                ForEach(used) { listing in
                    if let type = AircraftCatalog.type(listing.typeID), let fit = fits[type.id] {
                        UsedCard(session: session, listing: listing, type: type, fit: fit)
                    }
                }
            } else {
                Text("New aircraft cost more and take longer to arrive, but come in perfect condition.").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                ForEach(new) { type in
                    if let fit = fits[type.id] { NewCard(session: session, type: type, fit: fit) }
                }
            }
            if (tab == 0 && used.isEmpty) || (tab == 1 && new.isEmpty) { emptyNote }
        }
    }

    /// Why the list is empty, and the way out.
    private var emptyNote: some View {
        let filtered = filter != MarketFilter()
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(filtered ? "Nothing for sale matches the search and filters." : (tab == 0 ? "No used aircraft for sale this week. New listings come every week, or look at the New tab." : "No new aircraft to order right now."))
                    .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                if filtered {
                    Button { filter = MarketFilter() } label: { HangarButtonText("Clear search and filters") }.buttonStyle(.small)
                }
            }
        }
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
        let delivery = HangarWords.delivery(type, in: world)
        Card {
            HStack(alignment: .top, spacing: 12) {
                AircraftSpriteView(family: type.family, branding: paint, pixel: 2, maxWidth: 130).frame(width: 130)
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.displayName.uppercased()).pixelFont(13.333).foregroundStyle(locked ? Theme.textMuted : Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let rare = listing.rare {
                        HStack(alignment: .top, spacing: 8) {
                            Tag(text: "Rare find", color: Theme.gold)
                            Text(Words.explain(rare)).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    SpecLine(type: type)
                    Text("\(Int(listing.ageYears)) years old, condition \(Int(listing.condition))%, arrives in \(Format.wait(minutes: Valuation.usedDeliveryMinutes(listing)))")
                        .pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    if listing.rare == .barnFind {
                        let cost = Restorations.cost(type: type, ageYears: listing.ageYears)
                        let days = Restorations.days(ageYears: listing.ageYears, fasterHangar: false)
                        Text("It cannot fly until restored: about \(Format.compactMoney(cost)) and \(days) days in the hangar (half that with a hangar). Then it is near new, in the heritage livery.")
                            .pixelFont(10.667).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
                    }
                    FitSummary(fit: fit)
                    HangarDeliveryLine(delivery: delivery)
                    if !locked { HangarCrewLine(world: world, type: type) }
                    if listing.rare != nil { RewardButton(session: session, kind: .holdRareFind, target: listing.id) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HangarPriceColumn(priceText: Format.dollars(listing.price), price: listing.price, cash: world.airline.cash,
                                  neededLevel: locked ? type.level : nil, cannotDeliver: delivery.blocked != nil, action: "Buy") {
                    session.perform(sound: .coin) { _ = try $0.buyUsed(listingID: listing.id) }
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
        let delivery = HangarWords.delivery(type, in: world)
        Card {
            HStack(alignment: .top, spacing: 12) {
                AircraftSpriteView(family: type.family, branding: world.airline.branding, pixel: 2, maxWidth: 130).frame(width: 130)
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.displayName.uppercased()).pixelFont(13.333).foregroundStyle(locked ? Theme.textMuted : Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    SpecLine(type: type)
                    Text("Arrives in about \(Format.wait(minutes: Valuation.newDeliveryMinutes(level: type.level)))").pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    FitSummary(fit: fit)
                    HangarDeliveryLine(delivery: delivery)
                    if !locked { HangarCrewLine(world: world, type: type) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HangarPriceColumn(priceText: Format.compactMoney(type.priceUSD), price: type.priceUSD, cash: world.airline.cash,
                                  neededLevel: locked ? type.level : nil, cannotDeliver: delivery.blocked != nil, action: "Order") {
                    session.perform(sound: .coin) { _ = try $0.orderNew(typeID: type.id) }
                }
            }
        }
    }
}

/// Keeps how every aircraft type fits the airline's airports. It is worked out again only when the airports, the bases, the
/// level or the game mode change (all things the player does), not on every clock tick.
@MainActor
final class FitCache {
    static let shared = FitCache()

    struct Key: Hashable {
        var airports: [String]
        var bases: [Base]
        var level: Int
        var mode: GameMode
    }

    private var key: Key?
    private var saved: [String: AircraftFit] = [:]

    func table(_ world: World) -> [String: AircraftFit] {
        let airports = world.networkAirports
        let now = Key(airports: airports, bases: world.ops.bases, level: world.airline.level, mode: world.ops.mode)
        if now == key { return saved }
        var fresh: [String: AircraftFit] = [:]
        for type in AircraftCatalog.all { fresh[type.id] = world.fit(of: type, airports: airports) }
        key = now
        saved = fresh
        return fresh
    }
}

/// Words for the hangar.
enum HangarWords {
    /// Where a bought aircraft of this type would arrive, or why it cannot be bought at all.
    struct Delivery {
        /// Why no airport of the network can take it (World.deliveryProblem, the check buyUsed and orderNew make), in words.
        /// Nil when it can be delivered.
        var blocked: String?
        /// Where it arrives when that is not the home airport (a floatplane goes to the nearest water base, for example).
        var elsewhere: String?
    }

    static func delivery(_ type: AircraftType, in world: World) -> Delivery {
        if let blocked = DeliveryWords.problem(world, type: type) { return Delivery(blocked: blocked, elsewhere: nil) }
        return Delivery(blocked: nil, elsewhere: DeliveryWords.arrival(world, type: type))
    }
}

/// Under a card's details: the reason in red when the aircraft cannot be delivered, or where it arrives when that is not home.
struct HangarDeliveryLine: View {
    let delivery: HangarWords.Delivery
    var body: some View {
        if let blocked = delivery.blocked {
            Text(blocked).pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
        } else if let elsewhere = delivery.elsewhere {
            Text(elsewhere).pixelFont(10.667).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Under a card's details: about what hiring its pilots costs on top of the price (World.crewHireEstimate: automatic hiring
/// on, spare pilots rated on the type go first). Nothing when no one would be hired.
struct HangarCrewLine: View {
    let world: World
    let type: AircraftType
    var body: some View {
        let crew = world.crewHireEstimate(for: type)
        if crew.pilots > 0 {
            Text("Plus about \(Format.compactMoney(crew.fee)) to hire \(crew.pilots) pilot\(crew.pilots == 1 ? "" : "s") when it arrives.")
                .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
        }
    }
}
