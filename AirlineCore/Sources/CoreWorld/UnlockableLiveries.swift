// CoreWorld/UnlockableLiveries.swift: paint schemes the player earns: classic schemes from daily dispatch stamps
// (DailyDispatch.swift) and one scheme per seasonal event (SeasonalEvents.swift). Each is a code; the app names it.
// Unlocked codes are kept in Operations.unlockedLiveries. Every scheme carries the airline's own logo on the tail.
import CoreCatalog

public enum UnlockableLiveries {
    /// Classic schemes, in the order stamps unlock them.
    public static let classicCodes = ["classic.cheatline", "classic.sunset", "classic.forest", "classic.midnight", "classic.teal", "classic.polar"]

    /// The code of a seasonal event's scheme.
    public static func seasonCode(_ kind: SeasonKind) -> String { "season.\(kind.rawValue)" }

    /// Every code there is, classics first.
    public static var allCodes: [String] { classicCodes + SeasonKind.allCases.map(seasonCode) }

    /// The scheme for a code, with this logo on the tail. Nil for an unknown code.
    /// Colours are palette indexes (see PixelPalette): 5 pale grey, 6 white, 8 red, 10 orange, 11 amber, 12 cream,
    /// 13 forest, 15 lime, 16 deep teal, 17 teal, 18 mint, 19 navy, 21 sky, 23 indigo, 24 violet, 27 pink, 28 brown, 30 sand.
    public static func livery(code: String, logo: [UInt8]) -> SpecialLivery? {
        guard let p = paint(code) else { return nil }
        return SpecialLivery(name: code, branding: Branding(primary: p.0, secondary: p.1, accent: p.2, style: p.3, logo: logo))
    }

    static func paint(_ code: String) -> (Int, Int, Int, LiveryStyle)? {
        switch code {
        case "classic.cheatline": return (6, 10, 8, LiveryStyle.cheatline)
        case "classic.sunset": return (12, 8, 11, LiveryStyle.tailOnly)
        case "classic.forest": return (5, 13, 15, LiveryStyle.belly)
        case "classic.midnight": return (19, 21, 11, LiveryStyle.fullBody)
        case "classic.teal": return (6, 16, 17, LiveryStyle.splitBody)
        case "classic.polar": return (5, 19, 21, LiveryStyle.topStripe)
        case "season.newYearRush": return (8, 11, 12, LiveryStyle.fullBody)
        case "season.springBreak": return (6, 27, 18, LiveryStyle.cheatline)
        case "season.summerPeak": return (6, 17, 11, LiveryStyle.belly)
        case "season.harvestFreight": return (30, 28, 11, LiveryStyle.splitBody)
        case "season.festivalSeason": return (23, 24, 11, LiveryStyle.topStripe)
        case "season.holidayParcels": return (13, 8, 12, LiveryStyle.cheatline)
        default: return nil
        }
    }
}

extension World {
    /// The schemes this airline has earned, in the order they were earned.
    public var unlockedLiveries: [String] { ops.unlockedLiveries }

    /// Adds a scheme to the unlocked list. False if it was already there or the code is unknown.
    @discardableResult
    mutating func unlockLivery(_ code: String) -> Bool {
        guard UnlockableLiveries.paint(code) != nil, !ops.unlockedLiveries.contains(code) else { return false }
        ops.unlockedLiveries.append(code)
        return true
    }

    /// Paints one aircraft in an earned scheme (with the airline's current logo).
    public mutating func paintEarnedLivery(code: String, aircraftID: Int) throws {
        guard ops.unlockedLiveries.contains(code), let livery = UnlockableLiveries.livery(code: code, logo: airline.branding.logo) else {
            throw WorldError.invalidChoice
        }
        try setLivery(aircraftID: aircraftID, livery: livery)
    }
}
