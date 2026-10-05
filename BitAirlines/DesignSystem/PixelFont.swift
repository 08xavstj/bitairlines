import SwiftUI
import CoreText
import UIKit

/// RingPixel: a 5x7 pixel font shared with Ring Legacy (built by that project's `tools/make_pixel_font.py`). One font pixel is 1/8 of the point size, so sizes
/// of 8/3 points times a whole number land on whole device pixels on a 3x iPhone: 10.667, 13.333, 16, 21.333, 24, 32, 40, 48.
enum PixelFont {
    static let name = "RingPixel-Regular"
    /// The sizes the game uses (each is a whole number of device pixels per font pixel on a 3x screen).
    static let sizes: [CGFloat] = [8, 10.667, 13.333, 16, 21.333, 24, 32, 40, 48, 64]

    /// Registers the bundled font with the process (call once at launch).
    static func register() {
        guard let url = Bundle.main.url(forResource: "RingPixel", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func snapped(_ size: CGFloat) -> CGFloat { sizes.min { abs($0 - size) < abs($1 - size) } ?? size }

    static func font(_ size: CGFloat) -> Font { .custom(name, fixedSize: snapped(size)) }

    static func uiFont(_ size: CGFloat) -> UIFont { UIFont(name: name, size: snapped(size)) ?? .monospacedSystemFont(ofSize: size, weight: .bold) }
}

// MARK: - Text size (Dynamic Type)

/// The game's text is drawn in whole pixels, so it cannot stretch smoothly. Instead the whole UI steps up through the pixel sizes:
/// step 0 is normal, 1 is about a quarter larger, 2 about half again and 3 double. The step comes from the larger of the iPhone's text size
/// setting and the game's own Text size setting.
extension PixelFont {
    static let stepFactors: [CGFloat] = [1, 1.25, 1.5, 2]
    static let maxStep = stepFactors.count - 1

    /// The crisp size to use for a requested size at a text-size step.
    static func scaled(_ size: CGFloat, step: Int) -> CGFloat {
        let base = snapped(size)
        let target = base * stepFactors[max(0, min(maxStep, step))]
        return sizes.min { abs($0 - target) != abs($1 - target) ? abs($0 - target) < abs($1 - target) : $0 > $1 } ?? base
    }

    /// The step an iPhone text size asks for.
    static func step(for size: DynamicTypeSize) -> Int {
        switch size {
        case .xSmall, .small, .medium, .large: 0
        case .xLarge, .xxLarge: 1
        case .xxxLarge, .accessibility1: 2
        default: 3
        }
    }
}

private struct PixelStepKey: EnvironmentKey { static let defaultValue = 0 }

extension EnvironmentValues {
    /// How many sizes the pixel text is stepped up (0...3).
    var pixelStep: Int {
        get { self[PixelStepKey.self] }
        set { self[PixelStepKey.self] = newValue }
    }
}

struct PixelFontModifier: ViewModifier {
    let size: CGFloat
    @Environment(\.pixelStep) var step
    func body(content: Content) -> some View { content.font(PixelFont.font(PixelFont.scaled(size, step: step))) }
}

extension View {
    /// The game's text at a pixel size, stepped up with the player's text size.
    func pixelFont(_ size: CGFloat) -> some View { modifier(PixelFontModifier(size: size)) }
}
