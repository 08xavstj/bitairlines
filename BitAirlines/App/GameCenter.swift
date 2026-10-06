import GameKit
import Observation
import UIKit
import CoreWorld

/// Game Center: sign-in, three leaderboards and a handful of achievements.
///
/// Needs the Game Center entitlement (`CLOUD_FEATURES` in tools/generate_xcodeproj.rb) and the IDs below created in
/// App Store Connect (see docs/app-store.md). Without them, or when the player is not signed in, every call does nothing.
@MainActor
@Observable
final class GameCenter {
    static let shared = GameCenter()

    enum Board {
        static let revenue = "ca.amaruq.bitairlines.revenue"
        static let fleet = "ca.amaruq.bitairlines.fleet"
        /// Weekly goals met in one game.
        static let goals = "ca.amaruq.bitairlines.goals"
    }

    enum Achievement {
        static let firstRoute = "ca.amaruq.bitairlines.firstroute"
        static let tenAircraft = "ca.amaruq.bitairlines.tenaircraft"
        static func level(_ n: Int) -> String { "ca.amaruq.bitairlines.level\(n)" }
        static func scenario(_ id: ScenarioID) -> String { "ca.amaruq.bitairlines.scenario.\(id.rawValue)" }
    }

    /// Seconds between leaderboard updates while playing.
    private let reportInterval: TimeInterval = 300
    @ObservationIgnored private var lastReport = Date.distantPast
    @ObservationIgnored private var reported: Set<String> = []
    private(set) var isSignedIn = false

    /// Starts the sign-in. iOS shows its own sign-in sheet the first time, and the small welcome banner after that.
    func signIn() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            Task { @MainActor in
                if let viewController {
                    GameCenter.topViewController()?.present(viewController, animated: true)
                    return
                }
                self?.isSignedIn = GKLocalPlayer.local.isAuthenticated
            }
        }
    }

    /// Opens the Game Center dashboard (leaderboards and achievements).
    func showDashboard() {
        guard isSignedIn else { return }
        GKAccessPoint.shared.trigger(state: .dashboard) {}
    }

    /// Sends scores and unlocks achievements for this game. Cheap to call often: it only talks to Game Center every few minutes,
    /// or at once with `now` (leaving the game).
    func report(_ world: World, now: Bool = false) {
        guard isSignedIn, now || Date().timeIntervalSince(lastReport) > reportInterval else { return }
        // Sandbox money is unlimited, so its games stay off the leaderboards.
        guard world.ops.mode != .sandbox else { return }
        lastReport = Date()
        let revenue = min(world.airline.stats.revenue, Int(Int32.max))
        GKLeaderboard.submitScore(revenue, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [Board.revenue]) { _ in }
        GKLeaderboard.submitScore(world.aircraft.count, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [Board.fleet]) { _ in }
        GKLeaderboard.submitScore(world.ops.goalsCompleted, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [Board.goals]) { _ in }

        var earned: [String] = []
        if !world.routes.isEmpty { earned.append(Achievement.firstRoute) }
        if world.aircraft.count >= 10 { earned.append(Achievement.tenAircraft) }
        if world.airline.level >= 2 { earned += (2...world.airline.level).map(Achievement.level) }
        if let state = world.ops.scenario, state.medal != nil { earned.append(Achievement.scenario(state.id)) }
        let fresh = earned.filter { !reported.contains($0) }
        guard !fresh.isEmpty else { return }
        reported.formUnion(fresh)
        let achievements = fresh.map { id -> GKAchievement in
            let a = GKAchievement(identifier: id)
            a.percentComplete = 100
            a.showsCompletionBanner = true
            return a
        }
        GKAchievement.report(achievements) { _ in }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var top = scenes.flatMap(\.windows).first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
