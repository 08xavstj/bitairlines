import SwiftUI
import Observation

/// The game's text size setting (a step up through the pixel sizes).
enum TextSize: Int, CaseIterable, Identifiable {
    case standard, large, larger, largest
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .standard: "Normal"
        case .large: "Large"
        case .larger: "Larger"
        case .largest: "Largest"
        }
    }
}

/// Player preferences, stored on the device (not in a save): they follow the player across games.
@MainActor
@Observable
final class AppSettings {
    var textSize: TextSize { didSet { persist() } }
    /// Faint CRT scanlines over the whole game.
    var scanlines: Bool { didSet { persist() } }
    var haptics: Bool { didSet { persist() } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        textSize = TextSize(rawValue: defaults.integer(forKey: "settings.textSize")) ?? .standard
        scanlines = defaults.bool(forKey: "settings.scanlines")
        haptics = defaults.object(forKey: "settings.haptics") as? Bool ?? true
    }

    private func persist() {
        defaults.set(textSize.rawValue, forKey: "settings.textSize")
        defaults.set(scanlines, forKey: "settings.scanlines")
        defaults.set(haptics, forKey: "settings.haptics")
    }

    func tap() { if haptics { Platform.lightImpact() } }
}
