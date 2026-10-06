import Foundation

/// Keeps a copy of each save slot in the player's iCloud container, so a game follows them to a new iPhone or an iPad.
/// The copies sit in the app's private iCloud folder (not shown in the Files app).
///
/// Works only when the app is signed with the iCloud entitlement (`CLOUD_FEATURES` in tools/generate_xcodeproj.rb, which needs
/// a paid Apple Developer account). Without it, or when the player is signed out of iCloud, every call quietly does nothing.
final class CloudSaves {
    static let containerID = "iCloud.ca.amaruq.bitairlines"

    private let queue = DispatchQueue(label: "ca.amaruq.bitairlines.cloud")
    private var folder: URL?
    private var looked = false
    /// The player can turn syncing off in Settings.
    var enabled: () -> Bool = { true }

    /// The iCloud folder for saves, or nil without iCloud. Only call on `queue`: the first lookup can take a moment.
    private func cloudFolder() -> URL? {
        if looked { return folder }
        looked = true
        guard FileManager.default.ubiquityIdentityToken != nil,
              let base = FileManager.default.url(forUbiquityContainerIdentifier: CloudSaves.containerID) else { return nil }
        let dir = base.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent("Saves", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        folder = dir
        return dir
    }

    /// Copies a save to iCloud in the background.
    func upload(_ data: Data, name: String) {
        guard enabled() else { return }
        queue.async {
            guard let dir = self.cloudFolder() else { return }
            let target = dir.appendingPathComponent(name)
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &error) { url in
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    func delete(name: String) {
        queue.async {
            guard let dir = self.cloudFolder() else { return }
            let target = dir.appendingPathComponent(name)
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: target, options: .forDeleting, error: &error) { url in
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Reads the iCloud copies of these files (nil where there is none yet), then calls back on the main thread.
    /// A copy that is still downloading is asked for and picked up next time.
    func fetch(names: [String], done: @escaping ([String: Data]) -> Void) {
        guard enabled() else { done([:]); return }
        queue.async {
            var found: [String: Data] = [:]
            if let dir = self.cloudFolder() {
                for name in names {
                    let url = dir.appendingPathComponent(name)
                    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                    var error: NSError?
                    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { readURL in
                        if let data = try? Data(contentsOf: readURL) { found[name] = data }
                    }
                }
            }
            DispatchQueue.main.async { done(found) }
        }
    }
}
