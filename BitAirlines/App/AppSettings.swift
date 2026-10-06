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

/// How loud the game is, on top of the phone's own volume.
enum VolumeLevel: Int, CaseIterable, Identifiable {
    case low, medium, high
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
    var gain: Double {
        switch self {
        case .low: 0.35
        case .medium: 0.65
        case .high: 1.0
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
    var soundEffects: Bool { didSet { persist() } }
    var music: Bool { didSet { persist() } }
    var volume: VolumeLevel { didSet { persist() } }
    /// Copy saves to iCloud so they follow the player to another device.
    var iCloudSaves: Bool { didSet { persist() } }
    /// One note while the app is in the background, for the first thing that will need the player (Notifications.swift).
    var notifyAircraft: Bool { didSet { persist() } }
    /// A daily reminder that today's dispatch is ready. Off until the player turns it on.
    var notifyDaily: Bool { didSet { persist() } }
    /// The game has already asked, in its own dialog, whether to send notifications (it asks once, after the first breakdown or overdraft).
    var askedAboutNotifications: Bool { didSet { persist() } }

    /// Called after any setting changes, so the audio engine can follow.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        textSize = TextSize(rawValue: defaults.integer(forKey: "settings.textSize")) ?? .standard
        scanlines = defaults.bool(forKey: "settings.scanlines")
        haptics = defaults.object(forKey: "settings.haptics") as? Bool ?? true
        soundEffects = defaults.object(forKey: "settings.soundEffects") as? Bool ?? true
        music = defaults.object(forKey: "settings.music") as? Bool ?? true
        volume = VolumeLevel(rawValue: defaults.object(forKey: "settings.volume") as? Int ?? VolumeLevel.medium.rawValue) ?? .medium
        iCloudSaves = defaults.object(forKey: "settings.iCloudSaves") as? Bool ?? true
        notifyAircraft = defaults.object(forKey: "settings.notifyAircraft") as? Bool ?? true
        notifyDaily = defaults.bool(forKey: "settings.notifyDaily")
        askedAboutNotifications = defaults.bool(forKey: "settings.askedAboutNotifications")
    }

    private func persist() {
        defaults.set(textSize.rawValue, forKey: "settings.textSize")
        defaults.set(scanlines, forKey: "settings.scanlines")
        defaults.set(haptics, forKey: "settings.haptics")
        defaults.set(soundEffects, forKey: "settings.soundEffects")
        defaults.set(music, forKey: "settings.music")
        defaults.set(volume.rawValue, forKey: "settings.volume")
        defaults.set(iCloudSaves, forKey: "settings.iCloudSaves")
        defaults.set(notifyAircraft, forKey: "settings.notifyAircraft")
        defaults.set(notifyDaily, forKey: "settings.notifyDaily")
        defaults.set(askedAboutNotifications, forKey: "settings.askedAboutNotifications")
        onChange?()
    }

    func tap() { if haptics { Platform.lightImpact() } }
}
