import SwiftUI
import UIKit

/// The few things the game asks of the phone: screen density, Reduce Motion and the buzz of a button.
enum Platform {
    /// Device pixels per point (3 on most iPhones). The pixel art is scaled to whole device pixels, so this matters.
    @MainActor static var screenScale: CGFloat { UIScreen.main.scale }

    /// Whether the player asked the phone for less motion.
    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    @MainActor static func lightImpact() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    @MainActor static func heavyImpact() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    @MainActor static func successBuzz() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    @MainActor static func warningBuzz() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
