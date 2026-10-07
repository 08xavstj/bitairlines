import Foundation
import CoreWorld

/// What a save slot shows on the Continue screen. `broken` is a save the game can no longer read.
struct SaveSummary: Identifiable {
    let slot: Int
    let airlineName: String
    let date: CalendarDate?
    let cash: Int
    let aircraft: Int
    let level: Int
    let savedAt: Date
    var broken = false
    /// Whether the clock was running when the game was saved (nil for older saves).
    var clockRunning: Bool? = nil
    var id: Int { slot }
}

/// The few numbers the Continue screen shows, kept in a small file next to each save so the title screen never decodes whole worlds.
struct SaveSummaryFile: Codable {
    var airlineName: String
    var date: CalendarDate
    var cash: Int
    var aircraft: Int
    var level: Int
    var savedAt: Date
    /// Missing from older summary files.
    var clockRunning: Bool?
}

struct SaveEnvelope: Codable {
    /// The oldest reader that can open this save. Bump `SaveStore.formatVersion` when a save gains something an older build cannot
    /// read or would drop (a new case in a stored enum other than news, a new field that matters): an older build then leaves such
    /// a copy alone and tells the player to update, instead of failing or losing it.
    var formatVersion: Int
    var savedAt: Date
    /// One id per game, so iCloud never mixes up two different games that sit in the same slot on two devices.
    var gameID: String?
    /// The game clock when saved: older copies without `versions` are compared by this, not by the time of day.
    var progress: Int?
    /// How many saves of this game each device has made (SaveLineage): shows whether one copy was made from another.
    var versions: [String: Int]?
    /// Whether the clock was running when saved. Only a game left running moves on while the player is away.
    var clockRunning: Bool?
    var world: World
}

/// Saves live as JSON files in Application Support: one per slot, written atomically so a crash never leaves a half-written save.
/// With `cloud`, each game is also copied to iCloud (at most every few minutes, and always when the player leaves the game).
/// Bringing copies from other devices in, and keeping both when a game was played on two devices, is in SaveSync.swift.
final class SaveStore {
    static let slotCount = 3
    static let formatVersion = 1
    /// Seconds between iCloud copies of the same slot while playing.
    static let cloudInterval: TimeInterval = 180
    let directory: URL
    let cloud: CloudSaves?
    /// This device in the save counts. Kept in a file that is not backed up, so a phone restored from a backup counts as another device.
    let deviceID: String
    let tutorial: TutorialStore

    /// Main thread only: what the last iCloud sync found, and where to send words for the player (RootView shows them).
    var lastSync = SyncReport()
    var onNote: ((String) -> Void)?

    // Save queue only (SaveSync.swift uses these too).
    var lastUpload: [Int: Date] = [:]
    var gameIDs: [Int: String] = [:]
    var versions: [Int: [String: Int]] = [:]
    /// The slot of the game being played or being started. A sync never changes it.
    var openSlot: Int?
    /// Notes already given in this run of the app, so the same one does not come back at every sync.
    var announced: Set<String> = []
    private var pendingDeletes: Set<String>?
    /// Whether the game clock is running, as last told by the app (`noteClock`), for saves that do not say themselves.
    private var clockState: Bool?

    /// Every file read and write happens on this queue, one at a time, so saving while playing never holds up the screen and a
    /// read always sees the last write.
    let io = DispatchQueue(label: "ca.amaruq.bitairlines.saves")
    private let ioKey = DispatchSpecificKey<Bool>()

    init(directory: URL? = nil, cloud: CloudSaves? = nil, deviceID: String? = nil, tutorial: TutorialStore = TutorialStore()) {
        self.cloud = cloud
        self.tutorial = tutorial
        let dir: URL
        if let directory {
            dir = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            dir = base.appendingPathComponent("BitAirlines", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.directory = dir
        self.deviceID = deviceID ?? SaveStore.loadDeviceID(in: dir)
        io.setSpecific(key: ioKey, value: true)
    }

    /// This install's device id: made once, kept out of backups.
    private static func loadDeviceID(in directory: URL) -> String {
        var file = directory.appendingPathComponent("device-id.txt")
        if let id = try? String(contentsOf: file, encoding: .utf8), !id.isEmpty { return id }
        let id = UUID().uuidString
        try? id.write(to: file, atomically: true, encoding: .utf8)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? file.setResourceValues(values)
        return id
    }

    /// Runs on the save queue (at once if already on it).
    func onIO<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: ioKey) == true { return try body() }
        return try io.sync(execute: body)
    }

    static func fileName(slot: Int) -> String { "save-\(slot).json" }

    func url(slot: Int) -> URL { directory.appendingPathComponent(SaveStore.fileName(slot: slot)) }
    func backupURL(slot: Int) -> URL { directory.appendingPathComponent("save-\(slot).bak.json") }
    func summaryURL(slot: Int) -> URL { directory.appendingPathComponent("save-\(slot).summary.json") }
    var pendingDeletesURL: URL { directory.appendingPathComponent("deleted-games.json") }

    /// The game id of the save in a slot (made up for a save from before ids existed, and for a new game).
    func gameID(slot: Int) -> String { onIO { lockedGameID(slot: slot) } }

    func lockedGameID(slot: Int) -> String {
        if let id = gameIDs[slot] { return id }
        let id = (try? Data(contentsOf: url(slot: slot))).flatMap { SaveStamp.read($0)?.gameID } ?? UUID().uuidString
        gameIDs[slot] = id
        return id
    }

    /// The save counts of the copy in a slot (none for a save from before them).
    func lockedVersions(slot: Int) -> [String: Int] {
        if let counts = versions[slot] { return counts }
        let counts = (try? Data(contentsOf: url(slot: slot))).flatMap { SaveStamp.read($0)?.versions } ?? [:]
        versions[slot] = counts
        return counts
    }

    static func encode(_ envelope: SaveEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try encoder.encode(envelope)
    }

    static func decode(_ data: Data) throws -> SaveEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try decoder.decode(SaveEnvelope.self, from: data)
    }

    /// The app tells the store whenever the clock starts or stops (RootView follows the session's speed), so every save can say
    /// whether the game was running. A save that says so itself (`clockRunning`) wins over this.
    func noteClock(running: Bool?) {
        io.async { self.clockState = running }
    }

    /// Writes the slot. The first save of a session stays on the phone (the copy may be behind another device until the title
    /// screen has synced); after that iCloud gets a copy every few minutes, and at once with `toCloud`.
    func save(_ world: World, slot: Int, toCloud: Bool = false, clockRunning: Bool? = nil) throws {
        try onIO { try lockedSave(world, slot: slot, toCloud: toCloud, clockRunning: clockRunning) }
    }

    /// Saves on the save queue and returns at once. `failed` runs on the main thread if the save could not be written.
    func saveInBackground(_ world: World, slot: Int, toCloud: Bool, clockRunning: Bool? = nil, failed: @escaping () -> Void) {
        // iOS may suspend the app right after it goes to the background; ask for the moment the write needs.
        let time = BackgroundTime("Save game")
        io.async {
            do { try self.lockedSave(world, slot: slot, toCloud: toCloud, clockRunning: clockRunning) } catch { DispatchQueue.main.async { failed() } }
            time.end()
        }
    }

    private func lockedSave(_ world: World, slot: Int, toCloud: Bool, clockRunning: Bool?) throws {
        let id = lockedGameID(slot: slot)
        var counts = lockedVersions(slot: slot)
        counts[deviceID, default: 0] += 1
        let savedAt = Date()
        let running = clockRunning ?? clockState
        let envelope = SaveEnvelope(formatVersion: SaveStore.formatVersion, savedAt: savedAt, gameID: id, progress: world.clock.minute,
                                    versions: counts, clockRunning: running, world: world)
        let data = try SaveStore.encode(envelope)
        try data.write(to: url(slot: slot), options: .atomic)
        versions[slot] = counts
        writeSummary(SaveSummaryFile(airlineName: world.airline.name, date: world.clock.date, cash: world.airline.cash, aircraft: world.aircraft.count,
                                     level: world.airline.level, savedAt: savedAt, clockRunning: running), slot: slot)
        guard let cloud else { return }
        if lastUpload[slot] == nil && !toCloud { lastUpload[slot] = Date(); return }
        let due = lastUpload[slot].map { Date().timeIntervalSince($0) > SaveStore.cloudInterval } ?? true
        if toCloud || due {
            lastUpload[slot] = Date()
            cloud.upload(data, gameID: id, stamp: SaveStamp(envelope))
        }
    }

    func load(slot: Int) throws -> World {
        try onIO { try lockedLoad(slot: slot) }
    }

    /// Loads a game to play. Until `closeGame`, a sync leaves its slot alone, so a copy from another device can never replace the
    /// game while it is open (the two would fork instead, and the next sync keeps both).
    func open(slot: Int) throws -> World {
        try onIO {
            let world = try lockedLoad(slot: slot)
            openSlot = slot
            return world
        }
    }

    /// The player left the game.
    func closeGame() {
        onIO { openSlot = nil }
    }

    private func lockedLoad(slot: Int) throws -> World {
        let envelope = try SaveStore.decode(try Data(contentsOf: url(slot: slot)))
        if let id = envelope.gameID { gameIDs[slot] = id }
        versions[slot] = envelope.versions ?? [:]
        return envelope.world
    }

    private func writeSummary(_ summary: SaveSummaryFile, slot: Int) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(summary) { try? data.write(to: summaryURL(slot: slot), options: .atomic) }
    }

    func summary(slot: Int) -> SaveSummary? { onIO { lockedSummary(slot: slot) } }

    private func lockedSummary(slot: Int) -> SaveSummary? {
        guard FileManager.default.fileExists(atPath: url(slot: slot).path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let small = try? Data(contentsOf: summaryURL(slot: slot)), let s = try? decoder.decode(SaveSummaryFile.self, from: small) {
            return SaveSummary(slot: slot, airlineName: s.airlineName, date: s.date, cash: s.cash, aircraft: s.aircraft, level: s.level, savedAt: s.savedAt,
                               clockRunning: s.clockRunning)
        }
        // No summary yet (a save from before summaries, or one just brought in from iCloud): read the whole save once.
        guard let data = try? Data(contentsOf: url(slot: slot)) else { return nil }
        guard let envelope = try? SaveStore.decode(data) else {
            return SaveSummary(slot: slot, airlineName: "Save cannot be opened", date: nil, cash: 0, aircraft: 0, level: 0,
                               savedAt: SaveStamp.read(data)?.savedAt ?? Date.distantPast, broken: true)
        }
        let w = envelope.world
        writeSummary(SaveSummaryFile(airlineName: w.airline.name, date: w.clock.date, cash: w.airline.cash, aircraft: w.aircraft.count,
                                     level: w.airline.level, savedAt: envelope.savedAt, clockRunning: envelope.clockRunning), slot: slot)
        return SaveSummary(slot: slot, airlineName: w.airline.name, date: w.clock.date, cash: w.airline.cash, aircraft: w.aircraft.count, level: w.airline.level,
                           savedAt: envelope.savedAt, clockRunning: envelope.clockRunning)
    }

    func summaries() -> [SaveSummary] { (1...SaveStore.slotCount).compactMap { summary(slot: $0) } }

    /// Deletes the slot here, and the game in iCloud (with a marker so other devices do not send it back). While iCloud is off or
    /// out of reach the deletion is remembered and sent at the next sync, so the game does not come back. A save this version
    /// cannot read may be a newer game from another device: that one goes from this device only.
    func delete(slot: Int) {
        onIO {
            let id = lockedGameID(slot: slot)
            let readable = (try? Data(contentsOf: url(slot: slot))).flatMap { try? SaveStore.decode($0) } != nil
            for file in [url(slot: slot), summaryURL(slot: slot), backupURL(slot: slot)] { try? FileManager.default.removeItem(at: file) }
            gameIDs[slot] = nil
            versions[slot] = nil
            lastUpload[slot] = nil
            // The first-hour guide belonged to that airline, not to the slot.
            tutorial.setActive(false, slot: slot)
            guard readable else { return }
            var pending = lockedPendingDeletes()
            pending.insert(id)
            lockedSetPendingDeletes(pending)
            cloud?.delete(gameID: id)
        }
    }

    /// Games deleted here whose deletion iCloud has not shown yet.
    func lockedPendingDeletes() -> Set<String> {
        if let pendingDeletes { return pendingDeletes }
        let ids = (try? Data(contentsOf: pendingDeletesURL)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        pendingDeletes = Set(ids)
        return Set(ids)
    }

    func lockedSetPendingDeletes(_ ids: Set<String>) {
        pendingDeletes = ids
        if let data = try? JSONEncoder().encode(ids.sorted()) { try? data.write(to: pendingDeletesURL, options: .atomic) }
    }

    /// The first slot with nothing in it, or nil when all are taken (the player must delete a game first).
    func freeSlot() -> Int? { onIO { lockedFreeSlot() } }

    func lockedFreeSlot() -> Int? {
        (1...SaveStore.slotCount).first { $0 != openSlot && !FileManager.default.fileExists(atPath: url(slot: $0).path) }
    }

    /// Starts a fresh game in a slot: it gets a new id, so it can never be mistaken for the game that was there before, and a sync
    /// does not bring another game into the slot before its first save.
    func prepareNewGame(slot: Int) {
        onIO {
            gameIDs[slot] = UUID().uuidString
            versions[slot] = [:]
            lastUpload[slot] = nil
            openSlot = slot
        }
    }
}
