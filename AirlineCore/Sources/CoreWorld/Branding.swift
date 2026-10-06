// CoreWorld/Branding.swift: the airline's identity (colours, logo, livery style). Plain data: the app draws it onto every aircraft.
import CoreCatalog

public enum LiveryStyle: String, Sendable, Hashable, Codable, CaseIterable {
    case cheatline, belly, tailOnly, topStripe, fullBody, splitBody
}

public struct Branding: Sendable, Hashable, Codable {
    public static let logoSize = 24
    /// Logos from before the bigger canvas were 16 x 16; they load centred on the new one.
    static let oldLogoSize = 16

    /// Palette indexes (1...31, see PixelPalette). Primary is the fuselage or tail, secondary the stripe, accent the small details.
    public var primary: Int
    public var secondary: Int
    public var accent: Int
    public var style: LiveryStyle
    /// 16 x 16 palette indexes, row by row from the top left; 0 is transparent.
    public var logo: [UInt8]

    public init(primary: Int, secondary: Int, accent: Int, style: LiveryStyle, logo: [UInt8]) {
        self.primary = Branding.clampColour(primary)
        self.secondary = Branding.clampColour(secondary)
        self.accent = Branding.clampColour(accent)
        self.style = style
        self.logo = Branding.fixed(logo)
    }

    public static func clampColour(_ index: Int) -> Int { min(max(index, 1), PixelPalette.count - 1) }

    public static func blankLogo() -> [UInt8] { [UInt8](repeating: 0, count: logoSize * logoSize) }

    /// A logo of exactly logoSize x logoSize valid pixels (an old 16 x 16 logo is centred, other short input is padded, longer is
    /// cut, bad indexes become transparent).
    static func fixed(_ logo: [UInt8]) -> [UInt8] {
        if logo.count == oldLogoSize * oldLogoSize { return fixed(centred(logo)) }
        var out = Array(logo.prefix(logoSize * logoSize))
        while out.count < logoSize * logoSize { out.append(0) }
        return out.map { Int($0) < PixelPalette.count ? $0 : 0 }
    }

    /// An old 16 x 16 logo placed in the middle of the bigger canvas.
    static func centred(_ old: [UInt8]) -> [UInt8] {
        var out = blankLogo()
        let offset = (logoSize - oldLogoSize) / 2
        for y in 0..<oldLogoSize {
            for x in 0..<oldLogoSize { out[(y + offset) * logoSize + x + offset] = old[y * oldLogoSize + x] }
        }
        return out
    }

    enum CodingKeys: String, CodingKey { case primary, secondary, accent, style, logo }

    /// Decodes through the main initialiser, so a save from before the bigger canvas still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(primary: try c.decode(Int.self, forKey: .primary), secondary: try c.decode(Int.self, forKey: .secondary),
                  accent: try c.decode(Int.self, forKey: .accent), style: try c.decode(LiveryStyle.self, forKey: .style),
                  logo: try c.decode([UInt8].self, forKey: .logo))
    }

    public func logoPixel(x: Int, y: Int) -> Int {
        guard x >= 0, y >= 0, x < Branding.logoSize, y < Branding.logoSize else { return 0 }
        return Int(logo[y * Branding.logoSize + x])
    }

    public mutating func setLogoPixel(x: Int, y: Int, colour: Int) {
        guard x >= 0, y >= 0, x < Branding.logoSize, y < Branding.logoSize else { return }
        logo[y * Branding.logoSize + x] = UInt8(min(max(colour, 0), PixelPalette.count - 1))
    }

    /// The starting look: a white aircraft with a sky-blue cheat line and a simple wing mark on the tail.
    public static let starter = Branding(primary: PixelPalette.white, secondary: PixelPalette.sky, accent: PixelPalette.orange, style: .cheatline, logo: starterLogo)

    private static var starterLogo: [UInt8] {
        var b = blankLogo()
        let rows = [
            "................", "................", ".....aaaa.......", "....aaaaaa......", "...aaaaaaaa.....", "..aaaaaaaaaaa...", ".aaaaaaaaaaaaaa.", "..aaaaaaaaaaaa..",
            "...aaaaaaaaa....", "....aaaaaaa.....", ".....aaaaa......", "......aaa.......", "................", "................", "................", "................",
        ]
        let offset = (logoSize - oldLogoSize) / 2
        for (y, row) in rows.enumerated() { for (x, ch) in row.enumerated() where ch == "a" { b[(y + offset) * logoSize + x + offset] = UInt8(PixelPalette.sky) } }
        return b
    }
}

/// A one-off paint scheme on a single aircraft (retro, event or charter livery). Without one, the aircraft wears the airline's branding.
public struct SpecialLivery: Sendable, Hashable, Codable {
    public var name: String
    public var branding: Branding

    public init(name: String, branding: Branding) {
        self.name = name
        self.branding = branding
    }
}
