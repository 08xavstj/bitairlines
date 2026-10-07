import SwiftUI
import Observation
import CoreCatalog
import CoreWorld

enum GameSpeed: Int, CaseIterable, Identifiable {
    case paused, x1, x4, x16, x64
    var id: Int { rawValue }

    /// Game minutes that pass per real second.
    var minutesPerSecond: Double {
        switch self {
        case .paused: 0
        case .x1: 24
        case .x4: 96
        case .x16: 384
        case .x64: 1536
        }
    }

    var label: String {
        switch self {
        case .paused: "Pause"
        case .x1: "1x"
        case .x4: "4x"
        case .x16: "16x"
        case .x64: "64x"
        }
    }
}

/// One game in progress: owns the world, runs its clock at the chosen speed, and saves it.
@MainActor
@Observable
final class GameSession {
    /// The game as the views see it. Reading it always gives the latest state. The views are told it changed by `publish()`:
    /// on every clock tick while the map is up, a few times a second while a list screen is open (`PageWatch`), and at once after
    /// anything the player does (`perform` sets it) or when the clock stops for a problem.
    var world: World {
        get {
            access(keyPath: \.world)
            return live
        }
        set {
            withMutation(keyPath: \.world) { live = newValue }
            markPublished()
        }
    }
    var speed: GameSpeed = .paused
    /// A message about the last thing the player tried (for example why a purchase was refused).
    var notice: String?
    /// Money just earned from flights and jobs, shown next to the bank total for a moment.
    var payout: Payout?
    /// What happened while the player was away, until they close the summary.
    var away: AwayReport?
    /// Airports another screen asked the map to show (a job's pickup and drop-off). The shell opens the map, the map frames them.
    var mapFocus: [String]?
    let slot: Int
    /// Set by the game screen, so changes the player makes can be heard.
    @ObservationIgnored var audio: AudioEngine?

    /// The running game. The clock moves it on every tick without telling the views each time (see `world`).
    @ObservationIgnored private var live: World
    /// True when the clock has moved `live` since the views were last told.
    @ObservationIgnored private var unpublished = false
    @ObservationIgnored private var lastPublish = Date()
    /// True when `live` has changed since it was last written to disk.
    @ObservationIgnored private var unsaved = false
    /// The save that follows a player's action, a moment after it (several quick actions make one save).
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private let store: SaveStore
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var carry: Double = 0
    @ObservationIgnored private var lastSave = Date()
    @ObservationIgnored private var lastTick = Date()

    /// Seconds between clock ticks.
    static let tickSeconds = 0.066
    /// While a list screen is open, the views hear about the clock this often at most (a long list costs far more to redraw than
    /// the map).
    static let calmPublishSeconds = 0.25
    /// A clock with nothing to do (paused, or stopped by a problem) looks in this often; changing the speed wakes it at once.
    static let idleTickSeconds = 0.5
    /// The clock writes what changed this often, whether it runs or is paused (a change made while paused is not lost).
    static let autosaveSeconds = 45.0
    /// A player's action is written this long after it, so a run of quick taps costs one save.
    static let saveAfterActionSeconds = 2.0

    init(world: World, slot: Int, store: SaveStore) {
        self.live = world
        self.slot = slot
        self.store = store
    }

    var isPausedByIssue: Bool { world.isPausedByIssue }
    var isGameOver: Bool { world.isBankrupt }

    // MARK: Clock

    func start() {
        guard loop == nil else { return }
        lastTick = Date()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let idle = self?.clockIdle else { break }
                let seconds = idle ? GameSession.idleTickSeconds : GameSession.tickSeconds
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                // stop() cancels the loop: no tick after the save it makes.
                if Task.isCancelled { break }
                self?.tick()
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        save(toCloud: true)
    }

    func setSpeed(_ newSpeed: GameSpeed) {
        let wasIdle = clockIdle
        speed = newSpeed
        // A paused screen shows exactly where the clock stopped.
        if unpublished { publish() }
        if wasIdle && !clockIdle { wakeClock() }
    }

    /// True when the clock has nothing to move: paused, stopped by a problem, or the game is over.
    private var clockIdle: Bool { speed == .paused || live.isPausedByIssue || live.isBankrupt }

    /// Starts the clock loop again at once, so pressing a speed or answering a problem does not wait out an idle look-in.
    private func wakeClock() {
        guard loop != nil else { return }
        loop?.cancel()
        loop = nil
        start()
    }

    private func tick() {
        let now = Date()
        let dt = min(0.25, now.timeIntervalSince(lastTick))
        lastTick = now
        defer {
            publishIfDue(now)
            // Paused or running, what changed is written every so often (a paused game still takes the player's actions).
            if unsaved && now.timeIntervalSince(lastSave) > GameSession.autosaveSeconds { save() }
        }
        guard speed != .paused, !live.isBankrupt else { return }
        if live.isPausedByIssue { return }
        // The away summary and a perk choice cover the speed buttons: the game waits while they are up (the shell also pauses
        // the clock for them; this makes sure of it).
        if away != nil || !live.ops.perkChoices.isEmpty { return }
        carry += dt * speed.minutesPerSecond
        let minutes = Int(carry)
        guard minutes > 0 else { return }
        carry -= Double(minutes)
        let revenueBefore = live.airline.stats.revenue
        let result = live.advance(byMinutes: minutes)
        unpublished = true
        unsaved = true
        notePayout(live.airline.stats.revenue - revenueBefore, at: now)
        if result == .pausedForIssue || result == .gameOver {
            // Something waits for the player: show it now, not on the next look-in.
            publish()
            save()
        }
    }

    /// Tells the views what the clock changed: on every tick, or, while a list screen is open, a few times a second.
    private func publishIfDue(_ now: Date) {
        guard unpublished else { return }
        if PageWatch.shown == 0 || now.timeIntervalSince(lastPublish) >= GameSession.calmPublishSeconds { publish() }
    }

    /// Tells every view that reads `world` to draw again.
    private func publish() {
        withMutation(keyPath: \.world) {}
        markPublished()
    }

    private func markPublished() {
        unpublished = false
        lastPublish = Date()
    }

    /// Moves the game on for a break of this many real seconds and keeps a summary to show. A breakdown waits until the player is
    /// back (the rest of the fleet keeps flying); running out of money stops early.
    func catchUp(realSeconds: TimeInterval) {
        let minutes = AwayReport.gameMinutes(forRealSeconds: realSeconds)
        guard minutes >= AwayReport.minGameMinutes, !live.isBankrupt, !live.isPausedByIssue else { return }
        let before = live.airline.stats, cash = live.airline.cash, start = live.clock.minute
        let result = live.advanceAway(byMinutes: minutes)
        let after = live.airline.stats
        away = AwayReport(gameMinutes: live.clock.minute - start, flights: after.flights - before.flights, passengers: after.passengers - before.passengers,
                          revenue: after.revenue - before.revenue, cashChange: live.airline.cash - cash, stoppedForIssue: result == .pausedForIssue)
        unsaved = true
        publish()
        lastTick = Date()
        save()
    }

    /// Payments that land close together add up in one tag, so fast speeds do not flicker.
    private func notePayout(_ amount: Int, at now: Date) {
        guard amount > 0 else { return }
        if let current = payout, now.timeIntervalSince(current.shownAt) < Payout.mergeSeconds {
            payout = Payout(id: current.id, amount: current.amount + amount, shownAt: current.shownAt)
        } else {
            payout = Payout(id: (payout?.id ?? 0) + 1, amount: amount, shownAt: now)
        }
    }

    /// `toCloud` also copies the save to iCloud now and sends Game Center scores (leaving, or the app going to the background).
    func save(toCloud: Bool = false) {
        pendingSave?.cancel()
        pendingSave = nil
        unsaved = false
        // Written on the save queue: encoding a big airline never holds up the screen.
        store.saveInBackground(live, slot: slot, toCloud: toCloud) { [weak self] in self?.notice = "Could not save the game." }
        lastSave = Date()
        GameCenter.shared.report(live, now: toCloud)
        if let state = live.ops.scenario, let medal = state.medal { ScenarioRecords.record(medal, for: state.id) }
    }

    /// Writes the game a moment after the player's last action, so what they did is on disk even while the clock is paused (the
    /// clock saves only what it moves). A run of quick actions makes one save.
    private func saveSoon() {
        unsaved = true
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(GameSession.saveAfterActionSeconds * 1_000_000_000))
            if Task.isCancelled { return }
            guard let self, self.unsaved else { return }
            self.save()
        }
    }

    // MARK: Actions (each wraps a World call and reports a refusal as a notice)

    /// Runs a change to the world; if the core refuses, the reason becomes a notice (and a refusal sound). `sound` plays when it goes through.
    /// Setting `world` tells the views at once, so the result of a tap shows on the next frame, whatever the clock is doing.
    /// A change that goes through is saved a moment later (`saveSoon`).
    @discardableResult
    func perform(sound: SoundEffect? = nil, _ change: (inout World) throws -> Void) -> Bool {
        // Answering a problem lets an idle clock run again: wake it now rather than at its next look-in.
        let wasIdle = clockIdle
        defer { if wasIdle && !clockIdle { wakeClock() } }
        do {
            try change(&world)
            notice = nil
            if let sound { audio?.play(sound) }
            saveSoon()
            return true
        } catch let error as WorldError {
            notice = Messages.describe(error, cash: live.airline.cash)
            audio?.play(.denied)
            return false
        } catch {
            notice = "That did not work."
            audio?.play(.denied)
            return false
        }
    }

    func resolve(issueID: Int, choice: IssueChoice) {
        perform { try $0.resolve(issueID: issueID, choice: choice) }
        save()
    }
}
