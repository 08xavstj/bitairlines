import Foundation
import CoreWorld

/// What a save slot shows on the Continue screen.
struct SaveSummary: Identifiable {
    let slot: Int
    let airlineName: String
    let date: CalendarDate
    let cash: Int
    let aircraft: Int
    let level: Int
    let savedAt: Date
    var id: Int { slot }
}

struct SaveEnvelope: Codable {
    var formatVersion: Int
    var savedAt: Date
    var world: World
}

/// Saves live as JSON files in Application Support: one per slot, written atomically so a crash never leaves a half-written save.
/// With `cloud`, each slot is also copied to iCloud (at most every few minutes, and always when the player leaves the game).
final class SaveStore {
    static let slotCount = 3
    static let formatVersion = 1
    /// Seconds between iCloud copies of the same slot while playing.
    static let cloudInterval: TimeInterval = 180
    let directory: URL
    let cloud: CloudSaves?
    private var lastUpload: [Int: Date] = [:]

    init(directory: URL? = nil, cloud: CloudSaves? = nil) {
        self.cloud = cloud
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("BitAirlines", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    static func fileName(slot: Int) -> String { "save-\(slot).json" }

    func url(slot: Int) -> URL { directory.appendingPathComponent(SaveStore.fileName(slot: slot)) }

    /// `toCloud` forces an iCloud copy now (leaving the game, the app going to the background).
    func save(_ world: World, slot: Int, toCloud: Bool = false) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(SaveEnvelope(formatVersion: SaveStore.formatVersion, savedAt: Date(), world: world))
        try data.write(to: url(slot: slot), options: .atomic)
        let due = lastUpload[slot].map { Date().timeIntervalSince($0) > SaveStore.cloudInterval } ?? true
        if let cloud, toCloud || due {
            lastUpload[slot] = Date()
            cloud.upload(data, name: SaveStore.fileName(slot: slot))
        }
    }

    /// Brings in iCloud copies that are newer than the ones on this phone (a game played on another device), and sends up local
    /// saves that iCloud does not have yet. Calls `done` on the main thread when finished.
    func syncWithCloud(done: @escaping () -> Void) {
        guard let cloud else { done(); return }
        let names = (1...SaveStore.slotCount).map { SaveStore.fileName(slot: $0) }
        cloud.fetch(names: names) { remote in
            for slot in 1...SaveStore.slotCount {
                let name = SaveStore.fileName(slot: slot)
                let local = try? Data(contentsOf: self.url(slot: slot))
                let localDate = local.flatMap(SaveStore.savedAt)
                let cloudDate = remote[name].flatMap(SaveStore.savedAt)
                if let data = remote[name], let cloudDate, localDate.map({ cloudDate > $0 }) ?? true {
                    try? data.write(to: self.url(slot: slot), options: .atomic)
                } else if let local, let localDate, cloudDate.map({ localDate > $0 }) ?? true {
                    cloud.upload(local, name: name)
                }
            }
            done()
        }
    }

    /// When a save file was written, read from inside the file (not the file system, which can change it when copying).
    static func savedAt(_ data: Data) -> Date? {
        struct Stamp: Decodable { var savedAt: Date }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Stamp.self, from: data))?.savedAt
    }

    func load(slot: Int) throws -> World {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url(slot: slot))
        return try decoder.decode(SaveEnvelope.self, from: data).world
    }

    func summary(slot: Int) -> SaveSummary? {
        guard FileManager.default.fileExists(atPath: url(slot: slot).path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url(slot: slot)), let envelope = try? decoder.decode(SaveEnvelope.self, from: data) else { return nil }
        let w = envelope.world
        return SaveSummary(slot: slot, airlineName: w.airline.name, date: w.clock.date, cash: w.airline.cash, aircraft: w.aircraft.count, level: w.airline.level, savedAt: envelope.savedAt)
    }

    func summaries() -> [SaveSummary] { (1...SaveStore.slotCount).compactMap { summary(slot: $0) } }

    func delete(slot: Int) {
        try? FileManager.default.removeItem(at: url(slot: slot))
        cloud?.delete(name: SaveStore.fileName(slot: slot))
    }

    /// The first slot with nothing in it (or the oldest save if all are full).
    func freeSlot() -> Int {
        for slot in 1...SaveStore.slotCount where !FileManager.default.fileExists(atPath: url(slot: slot).path) { return slot }
        return summaries().min { $0.savedAt < $1.savedAt }?.slot ?? 1
    }
}
