import SwiftUI
import CoreWorld

/// The player's real date for Core, which has no clock: days since 2000-01-01 on the player's local date.
/// Core does the counting (RealCalendar.realDay), so the app and Core always agree.
enum RealDay {
    /// Always counted on the Gregorian calendar, whatever calendar the phone is set to: the Japanese, Persian, Buddhist,
    /// Islamic or Republic of China calendars give a different year (8, 1405, 2569, 1448, 115), which would stop the real day.
    /// Only the time zone is taken from `calendar` (the player's own by default), so the day turns at local midnight.
    static func today(_ now: Date = Date(), calendar: Calendar = .current) -> Int {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: now)
        return RealCalendar.realDay(year: parts.year ?? RealCalendar.epochYear, month: parts.month ?? 1, day: parts.day ?? 1)
    }
}

/// Passes today's real day to the world: when the game opens, when the app comes back to the front, and every 30 seconds
/// (so midnight is noticed while playing). Draws nothing.
@MainActor
struct RealDaySync: View {
    let session: GameSession
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                while !Task.isCancelled {
                    sync()
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                }
            }
            .onChange(of: phase) { _, newPhase in
                if newPhase == .active { sync() }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Only a later day is passed in: the world ignores an earlier one (the clock set back), so there is nothing to send.
    private func sync() {
        let today = RealDay.today()
        guard today > session.world.realDay else { return }
        session.perform { $0.setRealDay(today) }
    }
}
