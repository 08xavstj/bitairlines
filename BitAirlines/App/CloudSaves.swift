import Foundation
import CoreWorld

/// Keeps a copy of each game in the player's iCloud container, so a game follows them to a new iPhone or an iPad.
/// Files are named by game (not by slot), so two devices with different games in slot 1 never overwrite each other:
/// `game-<id>.json` holds a save, `deleted-<id>` marks a game the player deleted.
///
/// Works only when the app is signed with the iCloud entitlement (`CLOUD_FEATURES` in tools/generate_xcodeproj.rb, which needs
/// a paid Apple Developer account). Without it, or when the player is signed out of iCloud, every call quietly does nothing.
final class CloudSaves {
    static let containerID = "iCloud.ca.amaruq.bitairlines"
    /// The Settings switch "Keep saves in iCloud" (AppSettings writes it). Read from UserDefaults, which any queue may read, so
    /// the switch counts from the first moment, before any screen has appeared.
    static let settingKey = "settings.iCloudSaves"

    private let queue = DispatchQueue(label: "ca.amaruq.bitairlines.cloud")
    private var folder: URL?

    /// The player can turn syncing off in Settings.
    var enabled: Bool { UserDefaults.standard.object(forKey: CloudSaves.settingKey) as? Bool ?? true }

    static func gameFile(_ id: String) -> String { "game-\(id).json" }
    static func deletedMarker(_ id: String) -> String { "deleted-\(id)" }
    /// How iCloud shows a file that is in the cloud but not downloaded to this device yet.
    static func placeholder(_ name: String) -> String { ".\(name).icloud" }

    /// The iCloud folder for saves, or nil without iCloud. Only call on `queue`: the lookup can take a moment. A failed lookup is
    /// tried again next time, so signing in to iCloud later works without restarting the game.
    private func cloudFolder() -> URL? {
        if let folder { return folder }
        guard FileManager.default.ubiquityIdentityToken != nil,
              let base = FileManager.default.url(forUbiquityContainerIdentifier: CloudSaves.containerID) else { return nil }
        let dir = base.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent("Saves", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        folder = dir
        return dir
    }

    /// Copies a save to iCloud in the background, but only over a copy it was made from (SaveLineage). A copy that moved on on
    /// another device, or one that is not downloaded here yet, is left alone; the next sync on the title screen sorts it out.
    /// Asks iOS for a little time so a save made as the app goes to the background still gets there.
    func upload(_ data: Data, gameID: String, stamp: SaveStamp) {
        guard enabled else { return }
        let time = BackgroundTime("iCloud save")
        queue.async {
            defer { time.end() }
            guard let dir = self.cloudFolder() else { return }
            let name = CloudSaves.gameFile(gameID)
            let target = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(CloudSaves.placeholder(name)).path) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: target)
                return
            }
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &error) { url in
                if let existing = try? Data(contentsOf: url), let theirs = SaveStamp.read(existing), !SaveLineage.mayReplace(theirs, with: stamp) { return }
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// Removes a game from iCloud and leaves a marker, so other devices do not send it back. Does nothing while iCloud is off or out
    /// of reach: SaveStore remembers the deletion and asks again at the next sync.
    func delete(gameID: String) {
        guard enabled else { return }
        queue.async {
            guard let dir = self.cloudFolder() else { return }
            let target = dir.appendingPathComponent(CloudSaves.gameFile(gameID))
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: target, options: .forDeleting, error: &error) { url in
                try? FileManager.default.removeItem(at: url)
            }
            try? Data().write(to: dir.appendingPathComponent(CloudSaves.deletedMarker(gameID)), options: .atomic)
        }
    }

    /// Everything in the iCloud saves folder (file name to contents), then calls back on the main thread. Files still in the
    /// cloud are asked for and picked up next time. `nil` means iCloud is not available, which is different from an empty folder.
    func fetchAll(done: @escaping ([String: Data]?) -> Void) {
        guard enabled else { done(nil); return }
        queue.async {
            guard let dir = self.cloudFolder() else { DispatchQueue.main.async { done(nil) }; return }
            var found: [String: Data] = [:]
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for raw in names.sorted() {
                // A file not downloaded yet shows as ".name.icloud": ask for the real file by its real name.
                if raw.hasPrefix("."), raw.hasSuffix(".icloud") {
                    let real = String(raw.dropFirst().dropLast(".icloud".count))
                    try? FileManager.default.startDownloadingUbiquitousItem(at: dir.appendingPathComponent(real))
                    continue
                }
                let url = dir.appendingPathComponent(raw)
                var error: NSError?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { readURL in
                    if let data = try? Data(contentsOf: readURL) { found[raw] = data }
                }
            }
            DispatchQueue.main.async { done(found) }
        }
    }
}

/// The few fields of a save needed to compare two copies without decoding the whole world.
struct SaveStamp: Decodable {
    var formatVersion: Int
    var savedAt: Date
    var gameID: String?
    /// The game clock (minutes) when saved: how far along the game is.
    var progress: Int?
    /// Saves per device (SaveLineage); missing from saves made before the counts.
    var versions: [String: Int]?
    /// Only the airline's name, for words about a copy this version cannot open.
    var world: WorldStamp?

    struct WorldStamp: Decodable {
        var airline: AirlineStamp?
    }

    struct AirlineStamp: Decodable {
        var name: String?
    }

    var airlineName: String? { world?.airline?.name }

    static func read(_ data: Data) -> SaveStamp? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SaveStamp.self, from: data)
    }
}

extension SaveStamp {
    init(_ envelope: SaveEnvelope) {
        self.init(formatVersion: envelope.formatVersion, savedAt: envelope.savedAt, gameID: envelope.gameID, progress: envelope.progress,
                  versions: envelope.versions, world: WorldStamp(airline: AirlineStamp(name: envelope.world.airline.name)))
    }
}
