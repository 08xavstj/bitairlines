import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// The look of the game: a night sky over the apron, drawn in chunky 8-bit style (pixel font, stepped corners, hard shadows, segmented bars).
/// Dark-first by design. No gradients: every surface is one flat colour.
enum Theme {
    static let background = Color(hex: 0x0B1020)
    static let surface = Color(hex: 0x141C33)
    static let surfaceRaised = Color(hex: 0x1E2846)
    static let accent = Color(hex: 0x4FB6F0)
    static let accentDark = Color(hex: 0x1F6FA0)
    /// Text and icons drawn on an accent-coloured button.
    static let onAccent = Color(hex: 0x0B1020)
    static let textPrimary = Color(hex: 0xEEF2FA)
    static let textMuted = Color(hex: 0x9AA7C2)
    static let good = Color(hex: 0x6FD08C)
    static let bad = Color(hex: 0xF0706A)
    static let info = Color(hex: 0x8FB8FF)
    static let gold = Color(hex: 0xFFD166)
    static let separator = Color(hex: 0xEEF2FA, opacity: 0.10)
    /// The one-pixel-wide light line around a panel.
    static let panelBorder = Color(hex: 0x34456E)
    static let panelHighlight = Color(hex: 0x4A5E92)
    static let shadow = Color.black.opacity(0.45)

    /// The pixel font at a size (snapped to one the font renders crisply at).
    static func pixel(_ size: CGFloat) -> Font { PixelFont.font(size) }
    static func title(_ size: CGFloat = 28) -> Font { PixelFont.font(size) }
    /// Numbers and short labels.
    static let number = PixelFont.font(13.333)
    static let body = PixelFont.font(10.667)
    static let label = PixelFont.font(13.333)
    static let heading = PixelFont.font(16)
}
