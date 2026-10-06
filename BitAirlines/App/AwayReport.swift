import Foundation
import CoreWorld

/// What the fleet did while the player was away from the game, shown when they come back.
struct AwayReport: Equatable {
    let gameMinutes: Int
    let flights: Int
    let passengers: Int
    let revenue: Int
    let cashChange: Int
    /// The catch-up stopped early because something needs the player.
    let stoppedForIssue: Bool

    /// Each real minute away moves the game on this many minutes (slower than 1x, so a long break is not a shock).
    static let gameMinutesPerRealMinute = 15.0
    /// The most a break can move the game on: two game days.
    static let maxGameMinutes = 2 * 1440
    /// Breaks that move the game less than this show nothing.
    static let minGameMinutes = 60

    /// Game minutes to run for a break of this many real seconds.
    static func gameMinutes(forRealSeconds seconds: TimeInterval) -> Int {
        min(maxGameMinutes, Int(seconds / 60 * gameMinutesPerRealMinute))
    }
}
