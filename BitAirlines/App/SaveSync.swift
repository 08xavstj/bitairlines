import Foundation
import CoreWorld

/// What the last iCloud sync found. RootView gives the notes to the player as dialogs; TitleView can show the rest under Continue.
struct SyncReport: Equatable {
    /// Games whose copy in iCloud needs a newer version of Pixel Props. Playing the copy here would fork the game, so Continue
    /// refuses it until the game is updated.
    var needsUpdate: Set<String> = []
    /// Airlines in iCloud that did not fit: every slot here is taken.
    var notBroughtIn: [String] = []
    /// Plain words for the player about this sync, each given once per run of the app.
    var notes: [String] = []
}

extension SaveStore {
    /// How long Continue waits for iCloud before opening the game anyway (the sync then finishes in the background and leaves
    /// the open game alone).
    static let continueCheckSeconds: TimeInterval = 3

    /// Brings games in from iCloud and sends games up, then calls `done` on the main thread (at once without iCloud).
    func syncWithCloud(done: @escaping () -> Void) {
        guard let cloud else { done(); return }
        cloud.fetchAll { files in
            guard let files else { done(); return }
            self.io.async {
                let report = self.merge(files, upload: { cloud.upload($0, gameID: $1, stamp: $2) }, delete: { cloud.delete(gameID: $0) })
                DispatchQueue.main.async {
                    self.lastSync = report
                    for note in report.notes { self.onNote?(note) }
                    done()
                }
            }
        }
    }

    /// The merge itself, on the save queue. `files` is the iCloud folder (file name to contents); `upload` and `delete` stand
    /// in for iCloud, so tests can run a sync without one.
    func merge(_ files: [String: Data], upload: @escaping (Data, String, SaveStamp) -> Void, delete: @escaping (String) -> Void) -> SyncReport {
        onIO { () -> SyncReport in
            var sync = SaveMerge(store: self, upload: upload, delete: delete)
            return sync.run(files)
        }
    }

    /// Puts a copy from iCloud into a slot, the file as it came (nothing is re-encoded). `replacing` keeps the file that was there
    /// as save-N.bak.json and leaves the first-hour guide alone (same airline); a game new to this device gets no guide.
    func lockedPutCopy(_ data: Data, stamp: SaveStamp, slot: Int, replacing: Bool) -> Bool {
        if replacing {
            try? FileManager.default.removeItem(at: backupURL(slot: slot))
            try? FileManager.default.copyItem(at: url(slot: slot), to: backupURL(slot: slot))
        }
        do { try data.write(to: url(slot: slot), options: .atomic) } catch { return false }
        try? FileManager.default.removeItem(at: summaryURL(slot: slot))
        gameIDs[slot] = stamp.gameID
        versions[slot] = stamp.versions ?? [:]
        lastUpload[slot] = nil
        if !replacing { tutorial.setActive(false, slot: slot) }
        return true
    }
}

/// One sync with iCloud, on the save queue. The rules, in order: a game deleted on any device stays deleted; a copy made from
/// the one here that moved on replaces it (the old file is kept as a backup); a copy here that moved on goes up; two copies that
/// both moved on (SaveLineage.forked) are both kept, as two airlines; a copy this version cannot read is left alone and the
/// player is told; a game not on this device goes into a free slot. The slot of an open game is never written.
struct SaveMerge {
    let store: SaveStore
    let upload: (Data, String, SaveStamp) -> Void
    let delete: (String) -> Void
    var report = SyncReport()
    /// Game ids to leave alone: deleted on a device, or waiting to be deleted from here.
    var deleted: Set<String> = []
    /// The copies in iCloud by game id. Stamps only: a world is decoded only when it is about to be used.
    var remote: [String: (data: Data, stamp: SaveStamp)] = [:]
    /// Game ids in a slot here, including the ones this sync brings in.
    var here: Set<String> = []

    mutating func run(_ files: [String: Data]) -> SyncReport {
        readFolder(files)
        settleDeletes()
        for slot in 1...SaveStore.slotCount { mergeSlot(slot) }
        bringInNewGames()
        let fresh = report.notes.filter { !store.announced.contains($0) }
        store.announced.formUnion(fresh)
        report.notes = fresh
        return report
    }

    private mutating func readFolder(_ files: [String: Data]) {
        for name in files.keys.sorted() {
            guard let data = files[name] else { continue }
            if name.hasPrefix("deleted-") {
                deleted.insert(String(name.dropFirst("deleted-".count)))
            } else if name.hasPrefix("game-"), name.hasSuffix(".json"), let stamp = SaveStamp.read(data), let id = stamp.gameID {
                remote[id] = (data, stamp)
            }
        }
    }

    /// A deletion made while iCloud was off or out of reach is asked for again at every sync until its marker shows up.
    private mutating func settleDeletes() {
        var pending = store.lockedPendingDeletes()
        guard !pending.isEmpty else { return }
        for id in pending.sorted() {
            if deleted.contains(id) {
                pending.remove(id)
            } else {
                delete(id)
                deleted.insert(id)
            }
        }
        store.lockedSetPendingDeletes(pending)
    }

    private mutating func mergeSlot(_ slot: Int) {
        guard let local = try? Data(contentsOf: store.url(slot: slot)), let mine = SaveStamp.read(local) else { return }
        let id = store.lockedGameID(slot: slot)
        here.insert(id)
        if deleted.contains(id) { return }
        guard let theirs = remote[id] else {
            // Only on this device: send it up (CloudSaves leaves a copy alone that is still downloading).
            upload(local, id, mine)
            return
        }
        let name = theirs.stamp.airlineName ?? mine.airlineName ?? "An airline"
        if theirs.stamp.formatVersion > SaveStore.formatVersion {
            report.needsUpdate.insert(id)
            note("A newer copy of \(name) is in iCloud and needs a newer version of Pixel Props. Update the game to play it.")
            return
        }
        switch SaveLineage.compare(mine, theirs.stamp) {
        case .same:
            break
        case .ahead:
            upload(local, id, mine)
        case .behind:
            if slot == store.openSlot {
                note("A newer copy of \(name) from another device is in iCloud. Both copies are kept: the other one shows under Continue once you leave the game.")
                return
            }
            guard readable(theirs.data, name: name) else { return }
            _ = store.lockedPutCopy(theirs.data, stamp: theirs.stamp, slot: slot, replacing: true)
        case .forked:
            if slot == store.openSlot {
                note("\(name) was also played on another device. Both copies are kept: the other one shows under Continue once you leave the game.")
                return
            }
            keepBoth(slot: slot, local: local, theirs: theirs, name: name)
        }
    }

    /// Two copies that both moved on. The one here becomes its own game (a new id, so it goes up beside the other instead of
    /// fighting over one file); the one from iCloud comes in as the game it was, into a free slot.
    private mutating func keepBoth(slot: Int, local: Data, theirs: (data: Data, stamp: SaveStamp), name: String) {
        guard readable(theirs.data, name: name), var envelope = try? SaveStore.decode(local) else { return }
        let newID = UUID().uuidString
        envelope.gameID = newID
        envelope.versions = [store.deviceID: 1]
        guard let renamed = try? SaveStore.encode(envelope), (try? renamed.write(to: store.url(slot: slot), options: .atomic)) != nil else { return }
        store.gameIDs[slot] = newID
        store.versions[slot] = envelope.versions
        here.insert(newID)
        upload(renamed, newID, SaveStamp(envelope))
        let played = "\(name) was played on this device and on another one while they were out of touch."
        if let free = store.lockedFreeSlot(), store.lockedPutCopy(theirs.data, stamp: theirs.stamp, slot: free, replacing: false) {
            note(played + " Both copies are kept and show as two airlines under Continue. Keep the one you want and delete the other.")
        } else {
            report.notBroughtIn.append(name)
            note(played + " The copy from the other device could not be brought in yet.")
        }
    }

    private mutating func bringInNewGames() {
        for id in remote.keys.sorted() where !here.contains(id) && !deleted.contains(id) {
            guard let theirs = remote[id] else { continue }
            let name = theirs.stamp.airlineName ?? "An airline"
            if theirs.stamp.formatVersion > SaveStore.formatVersion {
                report.needsUpdate.insert(id)
                note("\(name) in iCloud needs a newer version of Pixel Props. Update the game to play it.")
                continue
            }
            guard let slot = store.lockedFreeSlot() else {
                report.notBroughtIn.append(name)
                continue
            }
            guard readable(theirs.data, name: name) else { continue }
            if store.lockedPutCopy(theirs.data, stamp: theirs.stamp, slot: slot, replacing: false) { here.insert(id) }
        }
        let left = report.notBroughtIn
        if left.count == 1 {
            note("One more airline is in iCloud (\(left[0])). Delete an airline here to bring it in.")
        } else if left.count > 1 {
            note("\(left.count) more airlines are in iCloud (\(left.joined(separator: ", "))). Delete an airline here to bring them in.")
        }
    }

    /// A copy this version cannot read in full is never used and never written over, and the player is told.
    private mutating func readable(_ data: Data, name: String) -> Bool {
        if (try? SaveStore.decode(data)) != nil { return true }
        note("The copy of \(name) in iCloud could not be read. It may come from a newer version of Pixel Props.")
        return false
    }

    private mutating func note(_ words: String) { report.notes.append(words) }
}
