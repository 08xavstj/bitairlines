import SwiftUI
import StoreKit
import CoreWorld

/// The wins that may bring up the App Store rating prompt: the first weekly goal met, certificate level 2, a scenario medal.
struct ReviewMoment: Equatable {
    var goalsCompleted: Int
    var level: Int
    var hasMedal: Bool

    init(_ world: World) {
        goalsCompleted = world.ops.goalsCompleted
        level = world.airline.level
        hasMedal = world.ops.scenario?.medal != nil
    }

    init(goalsCompleted: Int, level: Int, hasMedal: Bool) {
        self.goalsCompleted = goalsCompleted
        self.level = level
        self.hasMedal = hasMedal
    }

    /// True when this change is one of the wins.
    static func isWin(from old: ReviewMoment, to new: ReviewMoment) -> Bool {
        (old.goalsCompleted == 0 && new.goalsCompleted >= 1) || (old.level < 2 && new.level >= 2) || (!old.hasMedal && new.hasMedal)
    }

    /// Game minutes after a breakdown during which the game never asks.
    static let quietMinutesAfterBreakdown = 1440

    /// Never right after a loss: no problem waiting, money in the bank, no breakdown in the last game day.
    static func isCalm(_ world: World) -> Bool {
        guard !world.isBankrupt, !world.isPausedByIssue, world.airline.cash >= 0 else { return false }
        if world.issues.contains(where: { $0.isCritical }) { return false }
        let since = world.clock.minute - quietMinutesAfterBreakdown
        return !world.news.contains { $0.kind == .breakdown && $0.minute >= since }
    }
}

/// Remembers the app version the player was last asked in, so the prompt comes at most once per version.
struct ReviewStore {
    var defaults: UserDefaults = .standard
    private static let key = "review.askedVersion"

    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    func askedThisVersion(_ version: String = ReviewStore.appVersion) -> Bool { defaults.string(forKey: ReviewStore.key) == version }
    func markAsked(_ version: String = ReviewStore.appVersion) { defaults.set(version, forKey: ReviewStore.key) }
}

/// Sits behind the game screen and asks for a rating after a win, when nothing bad has just happened.
struct ReviewPromptWatcher: View {
    let session: GameSession
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        Color.clear
            .onChange(of: ReviewMoment(session.world)) { old, new in
                guard ReviewMoment.isWin(from: old, to: new) else { return }
                Task { @MainActor in
                    // Let the win sink in (and any perk choice open) before the system box appears.
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    let store = ReviewStore()
                    guard ReviewMoment.isCalm(session.world), !store.askedThisVersion() else { return }
                    store.markAsked()
                    requestReview()
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
