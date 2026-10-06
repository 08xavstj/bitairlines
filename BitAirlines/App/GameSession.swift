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
    var world: World
    var speed: GameSpeed = .paused
    /// A message about the last thing the player tried (for example why a purchase was refused).
    var notice: String?
    let slot: Int
    /// Set by the game screen, so changes the player makes can be heard.
    @ObservationIgnored var audio: AudioEngine?

    @ObservationIgnored private let store: SaveStore
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var carry: Double = 0
    @ObservationIgnored private var lastSave = Date()
    @ObservationIgnored private var lastTick = Date()

    init(world: World, slot: Int, store: SaveStore) {
        self.world = world
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
                try? await Task.sleep(nanoseconds: 66_000_000)
                self?.tick()
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        save()
    }

    func setSpeed(_ newSpeed: GameSpeed) { speed = newSpeed }

    private func tick() {
        let now = Date()
        let dt = min(0.25, now.timeIntervalSince(lastTick))
        lastTick = now
        guard speed != .paused, !world.isBankrupt else { return }
        if world.isPausedByIssue { return }
        carry += dt * speed.minutesPerSecond
        let minutes = Int(carry)
        guard minutes > 0 else { return }
        carry -= Double(minutes)
        let result = world.advance(byMinutes: minutes)
        if result == .pausedForIssue || result == .gameOver { save() }
        if now.timeIntervalSince(lastSave) > 45 { save() }
    }

    func save() {
        do { try store.save(world, slot: slot) } catch { notice = "Could not save the game." }
        lastSave = Date()
    }

    // MARK: Actions (each wraps a World call and reports a refusal as a notice)

    /// Runs a change to the world; if the core refuses, the reason becomes a notice (and a refusal sound). `sound` plays when it goes through.
    @discardableResult
    func perform(sound: SoundEffect? = nil, _ change: (inout World) throws -> Void) -> Bool {
        do {
            try change(&world)
            notice = nil
            if let sound { audio?.play(sound) }
            return true
        } catch let error as WorldError {
            notice = Messages.describe(error)
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
