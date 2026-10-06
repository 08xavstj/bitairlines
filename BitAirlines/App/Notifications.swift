import Foundation
import SwiftUI
import UserNotifications
import CoreWorld

/// One local notification to send: the words and how long from now.
struct AwayNote: Equatable {
    let title: String
    let body: String
    /// Real seconds from the moment the player leaves.
    let afterSeconds: TimeInterval
}

/// What to tell the player while they are away. The world is deterministic, so a copy run forward with the "while you were away"
/// rules (AwayReport) shows the first thing that will need them; its game time becomes real time at the same rate.
enum AwayNotes {
    /// Real seconds for a stretch of game minutes at the away rate (one game hour for each real minute).
    static func realSeconds(gameMinutes: Int) -> TimeInterval {
        Double(gameMinutes) / AwayReport.gameMinutesPerRealMinute * 60
    }

    /// The note for the first event ahead, or nil when nothing should be sent (the game is stopped or over).
    static func next(for world: World) -> AwayNote? {
        guard let event = world.firstEventNeedingPlayer(within: AwayReport.maxGameMinutes) else { return nil }
        let words = text(event.kind, world: world)
        return AwayNote(title: words.title, body: words.body, afterSeconds: max(60, realSeconds(gameMinutes: event.minutesAhead)))
    }

    /// Plain words, no exclamation marks.
    static func text(_ kind: LookaheadKind, world: World) -> (title: String, body: String) {
        let airline = world.airline.name
        switch kind {
        case .breakdown(let id):
            let registration = world.aircraft.first { $0.id == id }?.registration ?? "An aircraft"
            return ("\(registration) has broken down", "It is grounded until you choose a repair.")
        case .overdraft:
            return ("\(airline) is out of money", "Cash has gone past the overdraft limit. Take a loan or cut costs before the bank closes the airline.")
        case .bankruptcy:
            return ("\(airline) is about to close", "The bank has run out of patience. Open the game to see what is left.")
        case .jobLate(let jobID):
            if let job = world.ops.jobs.first(where: { $0.id == jobID }) {
                return ("\(Words.name(job.kind)) running late", "It will not reach \(Place.name(job.to)) in time. Late jobs pay half.")
            }
            return ("A job is running late", "It will not land in time. Late jobs pay half.")
        case .stopped:
            return ("The clock has stopped", "Something at \(airline) is waiting for your decision.")
        case .limitReached:
            return ("Your aircraft are waiting", "They have flown all they can while you were away. Open the game to keep them flying.")
        }
    }

    static let dailyTitle = "Today's dispatch is ready"
    static let dailyBody = "A new charter is waiting at the dispatch desk."
    /// Local time of the daily reminder.
    static let dailyHour = 9
}

/// Schedules and clears the game's local notifications. No server: everything is worked out on the phone.
/// At most two are ever pending: the next event and the daily reminder.
enum Notifier {
    static let eventID = "away.event"
    static let dailyID = "daily.dispatch"

    /// Asks iOS for permission (the system prompt). Calls back on the main thread with the answer.
    static func requestPermission(_ done: @escaping @MainActor (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in done(granted) }
        }
    }

    /// Replaces anything pending with the event note and, if wanted, the daily reminder.
    static func schedule(_ note: AwayNote?, daily: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        if let note {
            let content = UNMutableNotificationContent()
            content.title = note.title
            content.body = note.body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: note.afterSeconds, repeats: false)
            center.add(UNNotificationRequest(identifier: eventID, content: content, trigger: trigger))
        }
        if daily {
            let content = UNMutableNotificationContent()
            content.title = AwayNotes.dailyTitle
            content.body = AwayNotes.dailyBody
            var when = DateComponents()
            when.hour = AwayNotes.dailyHour
            when.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            center.add(UNNotificationRequest(identifier: dailyID, content: content, trigger: trigger))
        }
    }

    /// The player is back: nothing should arrive while they are playing.
    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}

/// Asks once, in the game's own words, whether to send notifications: after the first breakdown or overdraft, once the player
/// has dealt with it. Only a yes brings up the system prompt.
struct NotificationAsk: View {
    let session: GameSession
    @Environment(AppSettings.self) private var settings
    /// A breakdown or an overdraft has happened in this game.
    @State private var hadTrouble = false

    var body: some View {
        let world = session.world
        let show = hadTrouble && !settings.askedAboutNotifications && !world.isPausedByIssue && !world.isBankrupt && session.away == nil
        ZStack {
            if show { dialog }
        }
        .onChange(of: NotificationAsk.trouble(world), initial: true) { _, now in
            if now { hadTrouble = true }
        }
    }

    /// True when the world shows a breakdown or an overdraft.
    static func trouble(_ world: World) -> Bool {
        if world.news.contains(where: { $0.kind == .breakdown }) { return true }
        return world.issues.contains { issue in
            if case .overdraft = issue.kind { return true }
            return false
        }
    }

    private var dialog: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                Text("WHILE YOU ARE AWAY").pixelFont(16).foregroundStyle(Theme.accent)
                Text("Your aircraft keep flying when you leave the game. It can send you one short note when something needs you: a breakdown, money running out, a job running late. You can change this in Settings.")
                    .pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                Button("Tell me when an aircraft needs me") { answer(yes: true) }.buttonStyle(PrimaryButtonStyle())
                Button("Not now") { answer(yes: false) }.buttonStyle(SecondaryButtonStyle())
            }
            .padding(16).frame(maxWidth: 460)
            .background(PixelPanel(fill: Theme.surface, border: Theme.accent.opacity(0.7)))
            .padding(24)
            .accessibilityAddTraits(.isModal)
        }
    }

    private func answer(yes: Bool) {
        settings.askedAboutNotifications = true
        guard yes else {
            settings.notifyAircraft = false
            return
        }
        Notifier.requestPermission { granted in settings.notifyAircraft = granted }
    }
}
