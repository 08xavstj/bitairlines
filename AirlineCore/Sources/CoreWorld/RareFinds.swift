// CoreWorld/RareFinds.swift: now and then one used aircraft on the market is a rare find: a young low-hours aircraft at a
// discount, an old type in a historic paint scheme, or a cheap run-down project. All draws come from ops.rng, so the
// original market and simulation draws stay the same. Numbers are in Tuning ("Rare finds").
import CoreCatalog
import CoreSim

/// What makes a used listing special. Stored as an optional field on UsedListing, so older saves load without one.
public enum RareFind: String, Sendable, Hashable, Codable, CaseIterable {
    /// A young aircraft in near-perfect condition, priced well under its value.
    case lowHours
    /// An older type in a historic paint scheme; it arrives wearing that livery.
    case heritage
    /// A cheap aircraft in poor condition: a project for the hangar.
    case barnFind
}

public enum RareFinds {
    /// The name of the livery a heritage aircraft arrives in. A code: the app turns it into words.
    public static let heritageLiveryCode = "heritage"

    // Palette indexes for the historic scheme (see PixelPalette): cream fuselage, maroon cheat line, amber details.
    static let cream = 12
    static let maroon = 7
    static let amber = 11

    /// The historic paint scheme, with the airline's own mark on the tail.
    public static func heritageLivery(logo: [UInt8]) -> SpecialLivery {
        SpecialLivery(name: heritageLiveryCode, branding: Branding(primary: cream, secondary: maroon, accent: amber, style: .cheatline, logo: logo))
    }

    /// Share of the market value a rare find of this kind is priced at.
    public static func priceShare(_ kind: RareFind) -> Double {
        switch kind {
        case .lowHours: Tuning.rareLowHoursPriceShare
        case .heritage: Tuning.rareHeritagePriceShare
        case .barnFind: Tuning.rareBarnFindPriceShare
        }
    }

    /// The asking price for an aircraft of this type, age and condition.
    public static func price(_ kind: RareFind, type: AircraftType, ageYears: Double, condition: Double) -> Int {
        let value = Double(Valuation.value(type: type, ageYears: ageYears, condition: condition))
        return max(1, Int((value * priceShare(kind)).rounded()))
    }
}

extension World {
    /// The rare finds on the market now.
    public var rareListings: [UsedListing] { market.listings.filter { $0.rare != nil } }

    /// The weekly roll, run after the market turns over: sometimes one rare find comes up.
    mutating func rollRareFind() {
        guard ops.rng.chance(Tuning.rareFindChancePerWeek) else { return }
        let kind = RareFind.allCases[ops.rng.weightedIndex(Tuning.rareFindWeights)]
        addRareFind(kind)
    }

    /// Puts one rare find of this kind on the market for `Tuning.rareFindDays` and adds a news item.
    /// Only types the airline may fly now, and that can land at the home airport (where it is delivered), are offered.
    /// Returns the listing id, or nil when no type fits.
    @discardableResult
    mutating func addRareFind(_ kind: RareFind) -> Int? {
        let flyable = AircraftCatalog.available(atLevel: airline.level)
        let pool: [AircraftType]
        if let home = AirportCatalog.airport(airline.home) {
            pool = flyable.filter { canUse(type: $0, at: home) }
        } else {
            pool = flyable
        }
        guard !pool.isEmpty else { return nil }
        var preferred = pool
        switch kind {
        case .lowHours: preferred = pool.filter { $0.inProduction }
        case .heritage: preferred = pool.filter { !$0.inProduction }
        case .barnFind: break
        }
        let types = preferred.isEmpty ? pool : preferred
        let type = ops.rng.pick(types)

        let ages: ClosedRange<Double>
        let conditions: ClosedRange<Double>
        switch kind {
        case .lowHours:
            ages = Tuning.rareLowHoursAge
            conditions = Tuning.rareLowHoursCondition
        case .heritage:
            ages = type.inProduction ? Tuning.rareOldAgeInProduction : Tuning.rareOldAgeOutOfProduction
            conditions = Tuning.rareHeritageCondition
        case .barnFind:
            ages = type.inProduction ? Tuning.rareOldAgeInProduction : Tuning.rareOldAgeOutOfProduction
            conditions = Tuning.rareBarnFindCondition
        }
        let age = ops.rng.uniform(ages.lowerBound, ages.upperBound)
        let condition = ops.rng.uniform(conditions.lowerBound, conditions.upperBound)
        let delivery = ops.rng.int(2...9)
        let price = RareFinds.price(kind, type: type, ageYears: age, condition: condition)

        let id = market.nextListingID
        market.nextListingID += 1
        var listing = UsedListing(id: id, typeID: type.id, ageYears: age, condition: condition, price: price, deliveryDays: delivery)
        listing.rare = kind
        listing.rareUntilDay = clock.dayIndex + Tuning.rareFindDays
        market.listings.append(listing)
        // Reuses the milestone kind (the app's sound and inbox switches stay as they are): subject "rare:<kind>:<type id>".
        addNews(.milestone, subject: "rare:\(kind.rawValue):\(type.id)", amount: price)
        return id
    }
}
