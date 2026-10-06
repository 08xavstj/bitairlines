import SwiftUI
import CoreWorld

/// The player's real date for Core, which has no clock: days since 2000-01-01 in the local calendar.
/// Core does the counting (RealCalendar.realDay), so the app and Core always agree.
enum RealDay {
    static func today(_ now: Date = Date(), calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
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

    private func sync() {
        let today = RealDay.today()
        guard session.world.realDay != today else { return }
        session.perform { $0.setRealDay(today) }
    }
}
