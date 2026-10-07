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
    /// Registrations of aircraft that broke down during the break and still wait for a repair (the rest of the fleet kept flying).
    var heldBreakdowns: [String] = []

    /// Each real minute away moves the game on this many minutes: one game hour, a 24th of 1x. So 10 real minutes away fly
    /// 10 game hours, and 24 real minutes fly a whole game day.
    static let gameMinutesPerRealMinute = 60.0
    /// The most a break can move the game on: three game days, reached after maxGameMinutes / gameMinutesPerRealMinute =
    /// 4320 / 60 = 72 real minutes. A longer break (a night) pays the same as 72 minutes, and the "aircraft are waiting" note
    /// (Notifications.swift) comes at that point. The away reward (Tuning.awayRewardProfitDays) pays up to the same three days.
    static let maxGameMinutes = 3 * 1440
    /// Breaks that move the game less than this show nothing.
    static let minGameMinutes = 60

    /// Game minutes to run for a break of this many real seconds.
    static func gameMinutes(forRealSeconds seconds: TimeInterval) -> Int {
        min(maxGameMinutes, Int(seconds / 60 * gameMinutesPerRealMinute))
    }
}
