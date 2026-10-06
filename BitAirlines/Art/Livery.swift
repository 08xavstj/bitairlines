import SwiftUI
import UIKit
import CoreCatalog
import CoreWorld

/// Turns an aircraft drawing (rows of role characters) into a coloured picture for an airline's livery.
/// The role-to-colour rule is the same as `tools/art/preview.py`; change both together.
enum Livery {
    static let ink = 1, dark = 2, grey = 4, light = 5, white = 6, glass = 19

    /// Palette index for each role character under the branding's livery style.
    static func colours(for b: Branding) -> [Character: Int] {
        var map: [Character: Int] = ["k": ink, "g": glass, "d": dark, "n": grey, "v": grey, "w": light]
        let style: [Character: Int]
        switch b.style {
        case .cheatline: style = ["f": white, "u": light, "c": b.secondary, "t": b.primary, "m": b.primary, "l": b.primary]
        case .belly: style = ["f": white, "u": b.primary, "c": b.secondary, "t": b.primary, "m": b.accent, "l": b.primary]
        case .tailOnly: style = ["f": white, "u": light, "c": light, "t": b.primary, "m": b.secondary, "l": b.primary]
        case .topStripe: style = ["f": b.primary, "u": white, "c": b.secondary, "t": b.primary, "m": b.accent, "l": b.primary]
        case .fullBody: style = ["f": b.primary, "u": b.primary, "c": b.secondary, "t": b.secondary, "m": b.accent, "l": b.secondary]
        case .splitBody: style = ["f": b.primary, "u": b.secondary, "c": b.accent, "t": b.primary, "m": b.secondary, "l": b.primary]
        }
        for (key, value) in style { map[key] = value }
        return map
    }

    static func uiColor(_ paletteIndex: Int) -> UIColor {
        let rgb = PixelPalette.rgb(paletteIndex)
        return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    static func color(_ paletteIndex: Int) -> Color { Color(hex: PixelPalette.rgb(paletteIndex)) }

    // MARK: Side-view sprite

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        return c
    }()

    /// The last logo seen and its hash. Nearly every sprite wears the airline's own logo (the same array), so the hash of its 576
    /// pixels is worked out once, not for every aircraft on every redraw; comparing the same array again costs next to nothing.
    /// Behind a lock, because tests draw sprites from several threads at once.
    private static let logoLock = NSLock()
    private static var lastLogo: [UInt8] = []
    private static var lastLogoHash = 0

    private static func logoKey(_ logo: [UInt8]) -> Int {
        logoLock.lock()
        defer { logoLock.unlock() }
        if logo != lastLogo {
            lastLogo = logo
            lastLogoHash = logo.hashValue
        }
        return lastLogoHash
    }

    static func image(family: SpriteFamily, branding: Branding) -> UIImage? {
        let key = "\(family.rawValue)|\(branding.primary)|\(branding.secondary)|\(branding.accent)|\(branding.style.rawValue)|\(logoKey(branding.logo))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let rows = AircraftSpriteData.rows[family.rawValue] else { return nil }
        let image = render(rows: rows, logoRect: AircraftSpriteData.logoRects[family.rawValue] ?? [0, 0, 0, 0], branding: branding)
        cache.setObject(image, forKey: key)
        return image
    }

    private static func render(rows: [String], logoRect: [Int], branding: Branding) -> UIImage {
        let height = rows.count
        let width = rows.map(\.count).max() ?? 1
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let map = colours(for: branding)
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let g = context.cgContext
            g.setShouldAntialias(false)
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch != "." {
                    g.setFillColor(uiColor(map[ch] ?? white).cgColor)
                    g.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
            guard logoRect.count == 4, logoRect[2] > 0, logoRect[3] > 0 else { return }
            let rx = logoRect[0], ry = logoRect[1], rw = logoRect[2], rh = logoRect[3]
            for dy in 0..<rh {
                for dx in 0..<rw {
                    let u = min(Branding.logoSize - 1, (dx * Branding.logoSize + Branding.logoSize / 2) / rw)
                    let v = min(Branding.logoSize - 1, (dy * Branding.logoSize + Branding.logoSize / 2) / rh)
                    let pixel = branding.logoPixel(x: u, y: v)
                    guard pixel > 0 else { continue }
                    g.setFillColor(uiColor(pixel).cgColor)
                    g.fill(CGRect(x: rx + dx, y: ry + dy, width: 1, height: 1))
                }
            }
        }
    }

    // MARK: Map icon (top-down)

    static func sizeClass(seats: Int) -> String {
        if seats <= 10 { return "small" }
        if seats <= 50 { return "medium" }
        if seats <= 200 { return "large" }
        return "heavy"
    }

    static func mapIcon(sizeClass: String, branding: Branding) -> UIImage? {
        let key = "map|\(sizeClass)|\(branding.primary)|\(branding.secondary)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let rows = AircraftSpriteData.mapIcons[sizeClass] else { return nil }
        let height = rows.count
        let width = rows.map(\.count).max() ?? 1
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let map: [Character: Int] = ["P": branding.primary, "S": branding.secondary, "k": ink, "w": light, "n": grey]
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let g = context.cgContext
            g.setShouldAntialias(false)
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch != "." {
                    g.setFillColor(uiColor(map[ch] ?? white).cgColor)
                    g.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// An aircraft drawn in a livery, scaled up in whole pixels.
struct AircraftSpriteView: View {
    let family: SpriteFamily
    let branding: Branding
    /// Screen points per sprite pixel.
    var pixel: CGFloat = 2
    /// The widest it may be drawn (a card's sprite column). A bigger aircraft is drawn smaller to fit, in whole screen pixels.
    var maxWidth: CGFloat? = nil
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let image = Livery.image(family: family, branding: branding) {
            let scale = AircraftSpriteView.fitted(pixel: pixel, imageWidth: image.size.width, maxWidth: maxWidth, displayScale: displayScale)
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .frame(width: image.size.width * scale, height: image.size.height * scale)
                .accessibilityHidden(true)
        }
    }

    /// Points per sprite pixel so the sprite fits `maxWidth`: `pixel` when it fits, else the largest size that does and is still a
    /// whole number of screen pixels (so every sprite pixel is drawn the same size).
    static func fitted(pixel: CGFloat, imageWidth: CGFloat, maxWidth: CGFloat?, displayScale: CGFloat) -> CGFloat {
        guard let maxWidth, imageWidth > 0, imageWidth * pixel > maxWidth else { return pixel }
        let screen = max(1, displayScale)
        let devicePixels = max(1, (maxWidth / imageWidth * screen).rounded(.down))
        return devicePixels / screen
    }
}

/// The airline's 16 x 16 logo.
struct LogoView: View {
    let branding: Branding
    var pixel: CGFloat = 4
    var background: Color = Theme.surfaceRaised

    var body: some View {
        Canvas { context, _ in
            for y in 0..<Branding.logoSize {
                for x in 0..<Branding.logoSize {
                    let p = branding.logoPixel(x: x, y: y)
                    guard p > 0 else { continue }
                    context.fill(Path(CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: pixel, height: pixel)), with: .color(Livery.color(p)), style: FillStyle(antialiased: false))
                }
            }
        }
        .frame(width: CGFloat(Branding.logoSize) * pixel, height: CGFloat(Branding.logoSize) * pixel)
        .background(background)
        .accessibilityHidden(true)
    }
}

extension SpriteFamily {
    var sizeLabel: String {
        switch self {
        case .lightSingle, .utilitySingle, .floatSingle: "Light"
        case .twinTurboprop, .floatTwin, .taildragger, .commuter: "Commuter"
        case .regionalTurboprop, .regionalJet, .rearEngineMainline: "Regional"
        case .narrowbody: "Narrowbody"
        case .widebody: "Widebody"
        case .jumbo, .superJumbo: "Jumbo"
        }
    }
}
