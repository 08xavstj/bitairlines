import Foundation
import UIKit
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
}

struct SaveEnvelope: Codable {
    var formatVersion: Int
    var savedAt: Date
    /// One id per game, so iCloud never mixes up two different games that sit in the same slot on two devices.
    var gameID: String?
    /// The game clock when saved: two copies of the same game are compared by this, not by the time of day.
    var progress: Int?
    var world: World
}

/// Saves live as JSON files in Application Support: one per slot, written atomically so a crash never leaves a half-written save.
/// With `cloud`, each game is also copied to iCloud (at most every few minutes, and always when the player leaves the game).
final class SaveStore {
    static let slotCount = 3
    static let formatVersion = 1
    /// Seconds between iCloud copies of the same slot while playing.
    static let cloudInterval: TimeInterval = 180
    let directory: URL
    let cloud: CloudSaves?
    private var lastUpload: [Int: Date] = [:]
    private var gameIDs: [Int: String] = [:]
    /// Every file read and write happens on this queue, one at a time, so saving while playing never holds up the screen and a
    /// read always sees the last write.
    private let io = DispatchQueue(label: "ca.amaruq.bitairlines.saves")
    private let ioKey = DispatchSpecificKey<Bool>()

    init(directory: URL? = nil, cloud: CloudSaves? = nil) {
        self.cloud = cloud
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("BitAirlines", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        io.setSpecific(key: ioKey, value: true)
    }

    /// Runs on the save queue (at once if already on it).
    private func onIO<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: ioKey) == true { return try body() }
        return try io.sync(execute: body)
    }

    static func fileName(slot: Int) -> String { "save-\(slot).json" }

    func url(slot: Int) -> URL { directory.appendingPathComponent(SaveStore.fileName(slot: slot)) }
    func backupURL(slot: Int) -> URL { directory.appendingPathComponent("save-\(slot).bak.json") }
    func summaryURL(slot: Int) -> URL { directory.appendingPathComponent("save-\(slot).summary.json") }

    /// The game id of the save in a slot (made up for a save from before ids existed, and for a new game).
    func gameID(slot: Int) -> String { onIO { lockedGameID(slot: slot) } }

    private func lockedGameID(slot: Int) -> String {
        if let id = gameIDs[slot] { return id }
        let id = (try? Data(contentsOf: url(slot: slot))).flatMap { SaveStamp.read($0)?.gameID } ?? UUID().uuidString
        gameIDs[slot] = id
        return id
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

    /// Writes the slot. The first save of a session stays on the phone (the copy may be behind another device until the title
    /// screen has synced); after that iCloud gets a copy every few minutes, and at once with `toCloud`.
    func save(_ world: World, slot: Int, toCloud: Bool = false) throws {
        try onIO { try lockedSave(world, slot: slot, toCloud: toCloud) }
    }

    /// Saves on the save queue and returns at once. `failed` runs on the main thread if the save could not be written.
    func saveInBackground(_ world: World, slot: Int, toCloud: Bool, failed: @escaping () -> Void) {
        // iOS may suspend the app right after it goes to the background; ask for the moment the write needs.
        let task = UIApplication.shared.beginBackgroundTask(withName: "Save game")
        io.async {
            do { try self.lockedSave(world, slot: slot, toCloud: toCloud) } catch { DispatchQueue.main.async { failed() } }
            DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(task) }
        }
    }

    private func lockedSave(_ world: World, slot: Int, toCloud: Bool) throws {
        let id = lockedGameID(slot: slot)
        let progress = world.clock.minute
        let savedAt = Date()
        let data = try SaveStore.encode(SaveEnvelope(formatVersion: SaveStore.formatVersion, savedAt: savedAt, gameID: id, progress: progress, world: world))
        try data.write(to: url(slot: slot), options: .atomic)
        writeSummary(SaveSummaryFile(airlineName: world.airline.name, date: world.clock.date, cash: world.airline.cash,
                                     aircraft: world.aircraft.count, level: world.airline.level, savedAt: savedAt), slot: slot)
        guard let cloud else { return }
        if lastUpload[slot] == nil && !toCloud { lastUpload[slot] = Date(); return }
        let due = lastUpload[slot].map { Date().timeIntervalSince($0) > SaveStore.cloudInterval } ?? true
        if toCloud || due {
            lastUpload[slot] = Date()
            cloud.upload(data, gameID: id, progress: progress)
        }
    }

    /// Brings in games from iCloud: a newer copy of a game on this phone replaces it (the old file is kept as a backup), and a game
    /// this phone does not have goes into an empty slot. Games only on this phone are sent up. Deleted games stay deleted.
    func syncWithCloud(done: @escaping () -> Void) {
        guard let cloud else { done(); return }
        cloud.fetchAll { files in
            guard let files else { done(); return }
            self.io.async {
                self.merge(files, cloud: cloud)
                DispatchQueue.main.async { done() }
            }
        }
    }

    /// The iCloud merge itself, on the save queue.
    private func merge(_ files: [String: Data], cloud: CloudSaves) {
        do {
            let deleted = Set(files.keys.filter { $0.hasPrefix("deleted-") }.map { String($0.dropFirst("deleted-".count)) })
            var remote: [String: (data: Data, envelope: SaveEnvelope)] = [:]
            for (name, data) in files where name.hasPrefix("game-") && name.hasSuffix(".json") {
                // Only a copy this version can read in full is ever used.
                guard let envelope = try? SaveStore.decode(data), envelope.formatVersion <= SaveStore.formatVersion, let id = envelope.gameID else { continue }
                remote[id] = (data, envelope)
            }
            var here: Set<String> = []
            for slot in 1...SaveStore.slotCount {
                guard let local = try? Data(contentsOf: self.url(slot: slot)), let stamp = SaveStamp.read(local) else { continue }
                let id = self.lockedGameID(slot: slot)
                here.insert(id)
                if deleted.contains(id) { continue }
                let mine = stamp.progress ?? 0
                if let theirs = remote[id] {
                    let their = theirs.envelope.progress ?? 0
                    if their > mine {
                        try? FileManager.default.removeItem(at: self.backupURL(slot: slot))
                        try? FileManager.default.copyItem(at: self.url(slot: slot), to: self.backupURL(slot: slot))
                        try? theirs.data.write(to: self.url(slot: slot), options: .atomic)
                        try? FileManager.default.removeItem(at: self.summaryURL(slot: slot))
                    } else if mine > their {
                        cloud.upload(local, gameID: id, progress: mine)
                    }
                } else {
                    cloud.upload(local, gameID: id, progress: mine)
                }
            }
            for id in remote.keys.sorted() where !here.contains(id) && !deleted.contains(id) {
                guard let slot = self.lockedFreeSlot(), let theirs = remote[id] else { break }
                try? theirs.data.write(to: self.url(slot: slot), options: .atomic)
                try? FileManager.default.removeItem(at: self.summaryURL(slot: slot))
                self.gameIDs[slot] = id
            }
        }
    }

    func load(slot: Int) throws -> World {
        try onIO {
            let envelope = try SaveStore.decode(try Data(contentsOf: url(slot: slot)))
            if let id = envelope.gameID { gameIDs[slot] = id }
            return envelope.world
        }
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
            return SaveSummary(slot: slot, airlineName: s.airlineName, date: s.date, cash: s.cash, aircraft: s.aircraft, level: s.level, savedAt: s.savedAt)
        }
        // No summary yet (a save from before summaries, or one just brought in from iCloud): read the whole save once.
        guard let data = try? Data(contentsOf: url(slot: slot)) else { return nil }
        guard let envelope = try? SaveStore.decode(data) else {
            return SaveSummary(slot: slot, airlineName: "Save cannot be opened", date: nil, cash: 0, aircraft: 0, level: 0,
                               savedAt: SaveStamp.read(data)?.savedAt ?? Date.distantPast, broken: true)
        }
        let w = envelope.world
        writeSummary(SaveSummaryFile(airlineName: w.airline.name, date: w.clock.date, cash: w.airline.cash, aircraft: w.aircraft.count,
                                     level: w.airline.level, savedAt: envelope.savedAt), slot: slot)
        return SaveSummary(slot: slot, airlineName: w.airline.name, date: w.clock.date, cash: w.airline.cash, aircraft: w.aircraft.count, level: w.airline.level, savedAt: envelope.savedAt)
    }

    func summaries() -> [SaveSummary] { (1...SaveStore.slotCount).compactMap { summary(slot: $0) } }

    /// Deletes the slot here, and the game in iCloud (with a marker so other devices do not send it back).
    func delete(slot: Int) {
        onIO {
            let id = lockedGameID(slot: slot)
            try? FileManager.default.removeItem(at: url(slot: slot))
            try? FileManager.default.removeItem(at: summaryURL(slot: slot))
            gameIDs[slot] = nil
            lastUpload[slot] = nil
            cloud?.delete(gameID: id)
        }
    }

    /// The first slot with nothing in it, or nil when all are taken (the player must delete a game first).
    func freeSlot() -> Int? { onIO { lockedFreeSlot() } }

    private func lockedFreeSlot() -> Int? {
        (1...SaveStore.slotCount).first { !FileManager.default.fileExists(atPath: url(slot: $0).path) }
    }

    /// Starts a fresh game in a slot: it gets a new id, so it can never be mistaken for the game that was there before.
    func prepareNewGame(slot: Int) {
        onIO {
            gameIDs[slot] = UUID().uuidString
            lastUpload[slot] = nil
        }
    }
}
