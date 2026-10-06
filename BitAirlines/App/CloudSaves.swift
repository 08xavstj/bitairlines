import Foundation
import UIKit

/// Keeps a copy of each game in the player's iCloud container, so a game follows them to a new iPhone or an iPad.
/// Files are named by game (not by slot), so two devices with different games in slot 1 never overwrite each other:
/// `game-<id>.json` holds a save, `deleted-<id>` marks a game the player deleted.
///
/// Works only when the app is signed with the iCloud entitlement (`CLOUD_FEATURES` in tools/generate_xcodeproj.rb, which needs
/// a paid Apple Developer account). Without it, or when the player is signed out of iCloud, every call quietly does nothing.
final class CloudSaves {
    static let containerID = "iCloud.ca.amaruq.bitairlines"

    private let queue = DispatchQueue(label: "ca.amaruq.bitairlines.cloud")
    private var folder: URL?
    /// The player can turn syncing off in Settings.
    var enabled: () -> Bool = { true }

    static func gameFile(_ id: String) -> String { "game-\(id).json" }
    static func deletedMarker(_ id: String) -> String { "deleted-\(id)" }

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

    /// Copies a save to iCloud in the background, unless the copy already there is further along (a newer game from another
    /// device). Asks iOS for a little time so a save made as the app goes to the background still gets there.
    func upload(_ data: Data, gameID: String, progress: Int) {
        guard enabled() else { return }
        let task = UIApplication.shared.beginBackgroundTask(withName: "iCloud save")
        queue.async {
            defer { DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(task) } }
            guard let dir = self.cloudFolder() else { return }
            let target = dir.appendingPathComponent(CloudSaves.gameFile(gameID))
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &error) { url in
                if let existing = try? Data(contentsOf: url), let theirs = SaveStamp.read(existing)?.progress, theirs > progress { return }
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// Removes a game from iCloud and leaves a marker, so other devices do not send it back.
    func delete(gameID: String) {
        guard enabled() else { return }
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
        guard enabled() else { done(nil); return }
        queue.async {
            guard let dir = self.cloudFolder() else { DispatchQueue.main.async { done(nil) }; return }
            var found: [String: Data] = [:]
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for raw in names.sorted() {
                // A file not downloaded yet shows as ".name.icloud".
                if raw.hasPrefix("."), raw.hasSuffix(".icloud") {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: dir.appendingPathComponent(raw))
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

/// The few fields of a save needed to compare two copies without reading the whole world.
struct SaveStamp: Decodable {
    var formatVersion: Int
    var savedAt: Date
    var gameID: String?
    /// The game clock (minutes) when saved: how far along the game is.
    var progress: Int?

    static func read(_ data: Data) -> SaveStamp? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SaveStamp.self, from: data)
    }
}
