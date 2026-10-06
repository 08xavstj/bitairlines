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
final class SaveStore {
    static let slotCount = 3
    static let formatVersion = 1
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("BitAirlines", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func url(slot: Int) -> URL { directory.appendingPathComponent("save-\(slot).json") }

    func save(_ world: World, slot: Int) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(SaveEnvelope(formatVersion: SaveStore.formatVersion, savedAt: Date(), world: world))
        try data.write(to: url(slot: slot), options: .atomic)
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

    func delete(slot: Int) { try? FileManager.default.removeItem(at: url(slot: slot)) }

    /// The first slot with nothing in it (or the oldest save if all are full).
    func freeSlot() -> Int {
        for slot in 1...SaveStore.slotCount where !FileManager.default.fileExists(atPath: url(slot: slot).path) { return slot }
        return summaries().min { $0.savedAt < $1.savedAt }?.slot ?? 1
    }
}
