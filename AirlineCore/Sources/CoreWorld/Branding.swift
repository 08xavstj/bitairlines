// CoreWorld/Branding.swift: the airline's identity (colours, logo, livery style). Plain data: the app draws it onto every aircraft.
import CoreCatalog

public enum LiveryStyle: String, Sendable, Hashable, Codable, CaseIterable {
    case cheatline, belly, tailOnly, topStripe, fullBody, splitBody
}

public struct Branding: Sendable, Hashable, Codable {
    public static let logoSize = 16

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

    /// A logo of exactly 256 valid pixels (shorter input is padded, longer is cut, bad indexes become transparent).
    static func fixed(_ logo: [UInt8]) -> [UInt8] {
        var out = Array(logo.prefix(logoSize * logoSize))
        while out.count < logoSize * logoSize { out.append(0) }
        return out.map { Int($0) < PixelPalette.count ? $0 : 0 }
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
        for (y, row) in rows.enumerated() { for (x, ch) in row.enumerated() where ch == "a" { b[y * logoSize + x] = UInt8(PixelPalette.sky) } }
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
