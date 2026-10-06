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

    /// Each real minute away moves the game on this many minutes: one game hour, a 24th of 1x. Ten minutes away flies most
    /// of a game day, so the fleet has landed and been paid by the time the player is back.
    static let gameMinutesPerRealMinute = 60.0
    /// The most a break can move the game on: three game days (reached after three real hours), so a night away pays well
    /// without being worth more than playing.
    static let maxGameMinutes = 3 * 1440
    /// Breaks that move the game less than this show nothing.
    static let minGameMinutes = 60

    /// Game minutes to run for a break of this many real seconds.
    static func gameMinutes(forRealSeconds seconds: TimeInterval) -> Int {
        min(maxGameMinutes, Int(seconds / 60 * gameMinutesPerRealMinute))
    }
}
