import Testing
import Foundation
import CoreCatalog
import CoreWorld
@testable import BitAirlines

/// iCloud sync without iCloud: `SaveStore.merge` is fed the files a sync would find, and two stores in their own folders stand
/// in for two devices.
@Suite struct SaveSyncTests {
    /// A pretend iCloud folder with the same rule for writes as CloudSaves.upload: only over a copy the save was made from.
    final class FakeCloud {
        var files: [String: Data] = [:]
        var deleted: [String] = []

        func sync(_ store: SaveStore) -> SyncReport {
            store.merge(files, upload: { data, id, stamp in
                let name = CloudSaves.gameFile(id)
                if let existing = self.files[name], let theirs = SaveStamp.read(existing), !SaveLineage.mayReplace(theirs, with: stamp) { return }
                self.files[name] = data
            }, delete: { id in
                self.files[CloudSaves.gameFile(id)] = nil
                self.files[CloudSaves.deletedMarker(id)] = Data()
                self.deleted.append(id)
            })
        }

        var games: Int { files.keys.filter { $0.hasPrefix("game-") }.count }
    }

    /// A store in its own folder with its own guide flags, as on one device.
    static func device(_ id: String) -> SaveStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bitairlines-sync-\(UUID().uuidString)")
        let defaults = UserDefaults(suiteName: "bitairlines-sync-\(UUID().uuidString)") ?? .standard
        return SaveStore(directory: dir, deviceID: id, tutorial: TutorialStore(defaults: defaults))
    }

    static func world(_ name: String, seed: UInt64 = 11) throws -> World {
        try World.newGame(NewGameConfig(airlineName: name, airlineCode: "SY", homeAirport: "YEV", branding: .starter, difficulty: .easy, starterTypeID: "c208", seed: seed))
    }

    /// Loads a slot, runs a few days and saves it again, as a session on that device would.
    static func play(_ store: SaveStore, slot: Int, days: Int = 2) throws -> World {
        var w = try store.load(slot: slot)
        w.advance(byMinutes: days * 1440)
        try store.save(w, slot: slot)
        return w
    }

    /// The slot on `store` holding the same game as `slot` on `other`.
    static func slot(on store: SaveStore, matching slot: Int, of other: SaveStore) throws -> Int {
        try #require((1...SaveStore.slotCount).first { store.summary(slot: $0) != nil && store.gameID(slot: $0) == other.gameID(slot: slot) })
    }

    @Test func lineageTellsAheadBehindAndForked() {
        #expect(SaveLineage.compare(["a": 2], ["a": 2]) == .same)
        #expect(SaveLineage.compare(["a": 3], ["a": 2]) == .ahead)
        #expect(SaveLineage.compare(["a": 2, "b": 1], ["a": 2, "b": 4]) == .behind)
        #expect(SaveLineage.compare(["a": 3, "b": 1], ["a": 2, "b": 2]) == .forked)
        #expect(SaveLineage.compare([:], ["a": 1]) == .behind, "a copy never saved is behind one saved anywhere")
    }

    @Test func aGameFollowsThePlayerToASecondDevice() throws {
        let cloud = FakeCloud()
        let phone = SaveSyncTests.device("phone")
        let pad = SaveSyncTests.device("pad")
        try phone.save(try SaveSyncTests.world("Lineage Air"), slot: 1)
        #expect(cloud.sync(phone) == SyncReport())
        #expect(cloud.games == 1, "a game only here goes up")
        #expect(cloud.sync(pad) == SyncReport())
        #expect(pad.summary(slot: 1)?.airlineName == "Lineage Air", "and comes down into a free slot on the other device")
        #expect(phone.gameID(slot: 1) == pad.gameID(slot: 1))
        // Played on the pad, the newer copy replaces the phone's at its next sync.
        let played = try SaveSyncTests.play(pad, slot: 1)
        _ = cloud.sync(pad)
        _ = cloud.sync(phone)
        #expect(try phone.load(slot: 1).clock == played.clock)
        #expect(FileManager.default.fileExists(atPath: phone.backupURL(slot: 1).path), "the copy it replaced is kept as a backup")
    }

    @Test func twoCopiesThatBothMovedOnAreBothKept() throws {
        let cloud = FakeCloud()
        let phone = SaveSyncTests.device("phone")
        let pad = SaveSyncTests.device("pad")
        try phone.save(try SaveSyncTests.world("Fork Air"), slot: 1)
        _ = cloud.sync(phone)
        _ = cloud.sync(pad)
        // Both devices play on without a sync between them (the pad in the background, the phone on the train).
        let onPad = try SaveSyncTests.play(pad, slot: 1, days: 3)
        let onPhone = try SaveSyncTests.play(phone, slot: 1, days: 1)
        _ = cloud.sync(pad)
        let report = cloud.sync(phone)
        #expect(report.notes.count == 1 && report.notes[0].contains("two airlines"), "\(report.notes)")
        #expect(report.notBroughtIn.isEmpty && report.needsUpdate.isEmpty)
        let phoneClocks = try (1...2).map { try phone.load(slot: $0).clock.minute }
        #expect(Set(phoneClocks) == Set([onPhone.clock.minute, onPad.clock.minute]), "both copies are on the phone")
        #expect(phone.gameID(slot: 1) != phone.gameID(slot: 2) && cloud.games == 2, "and in iCloud as two games")
        // The pad picks up the phone's copy as a second airline too.
        _ = cloud.sync(pad)
        let padClocks = try (1...2).map { try pad.load(slot: $0).clock.minute }
        #expect(Set(padClocks) == Set(phoneClocks))
        #expect(cloud.sync(phone).notes.isEmpty && cloud.sync(pad).notes.isEmpty, "settled: nothing more to say")
    }

    @Test func aForkWithNoFreeSlotLeavesTheOtherCopyInICloud() throws {
        let cloud = FakeCloud()
        let phone = SaveSyncTests.device("phone")
        let pad = SaveSyncTests.device("pad")
        try phone.save(try SaveSyncTests.world("Full Air"), slot: 1)
        try phone.save(try SaveSyncTests.world("Second Air", seed: 12), slot: 2)
        try phone.save(try SaveSyncTests.world("Third Air", seed: 13), slot: 3)
        _ = cloud.sync(phone)
        _ = cloud.sync(pad)
        let padSlot = try SaveSyncTests.slot(on: pad, matching: 1, of: phone)
        _ = try SaveSyncTests.play(pad, slot: padSlot)
        _ = try SaveSyncTests.play(phone, slot: 1)
        _ = cloud.sync(pad)
        let report = cloud.sync(phone)
        #expect(report.notBroughtIn == ["Full Air"])
        #expect(report.notes.contains { $0.contains("Delete an airline here to bring it in") }, "\(report.notes)")
        #expect(phone.summaries().count == 3 && cloud.games == 4, "nothing is thrown away: the phone's copy went up as its own game")
    }

    @Test func aCopyFromANewerVersionIsLeftAloneAndNamed() throws {
        let cloud = FakeCloud()
        let phone = SaveSyncTests.device("phone")
        let w = try SaveSyncTests.world("Future Air")
        try phone.save(w, slot: 1)
        _ = cloud.sync(phone)
        let id = phone.gameID(slot: 1)
        // The other device has updated: its copy asks for a newer reader.
        var future = try SaveStore.decode(try #require(cloud.files[CloudSaves.gameFile(id)]))
        future.formatVersion = SaveStore.formatVersion + 1
        future.versions = ["phone": 1, "pad": 1]
        let futureData = try SaveStore.encode(future)
        cloud.files[CloudSaves.gameFile(id)] = futureData
        _ = try SaveSyncTests.play(phone, slot: 1)
        let report = cloud.sync(phone)
        #expect(report.needsUpdate == [id])
        #expect(report.notes.count == 1 && report.notes[0].contains("newer version"), "\(report.notes)")
        #expect(cloud.files[CloudSaves.gameFile(id)] == futureData, "the newer copy is not written over")
        #expect(try phone.load(slot: 1).clock.minute > w.clock.minute, "and the copy here is not replaced")
        // A game only in iCloud from a newer version is not brought in either, and is named once.
        let later = SaveEnvelope(formatVersion: SaveStore.formatVersion + 1, savedAt: Date(), gameID: "later", progress: 0, versions: ["pad": 1],
                                 clockRunning: nil, world: try SaveSyncTests.world("Later Air", seed: 14))
        cloud.files[CloudSaves.gameFile("later")] = try SaveStore.encode(later)
        let again = cloud.sync(phone)
        #expect(again.needsUpdate == [id, "later"] && phone.summaries().count == 1)
        #expect(again.notes.count == 1 && again.notes[0].contains("Later Air"), "the first note is not repeated: \(again.notes)")
    }

    @Test func aDeletionMadeWhileICloudWasOffStillHappens() throws {
        let cloud = FakeCloud()
        let phone = SaveSyncTests.device("phone")
        try phone.save(try SaveSyncTests.world("Gone Air"), slot: 1)
        _ = cloud.sync(phone)
        let id = phone.gameID(slot: 1)
        // Without iCloud (the switch off, or signed out) the delete is only local, and remembered.
        phone.delete(slot: 1)
        #expect(phone.summary(slot: 1) == nil)
        #expect(phone.onIO { phone.lockedPendingDeletes() } == [id])
        #expect(cloud.files[CloudSaves.gameFile(id)] != nil, "iCloud still has it")
        // iCloud is back: the next sync deletes it there instead of bringing it back here.
        let report = cloud.sync(phone)
        #expect(cloud.deleted == [id] && cloud.files[CloudSaves.deletedMarker(id)] != nil && cloud.files[CloudSaves.gameFile(id)] == nil)
        #expect(phone.summary(slot: 1) == nil && report.notes.isEmpty)
        #expect(phone.onIO { phone.lockedPendingDeletes() } == [id], "asked for, not yet seen done")
        _ = cloud.sync(phone)
        #expect(phone.onIO { phone.lockedPendingDeletes() }.isEmpty, "once the marker is seen the deletion is settled")
    }

    @Test func aGameBroughtInGetsNoGuideAndADeletedOneLosesIts() throws {
        let cloud = FakeCloud()
        let phone = SaveSyncTests.device("phone")
        let pad = SaveSyncTests.device("pad")
        try phone.save(try SaveSyncTests.world("Guide Air"), slot: 1)
        _ = cloud.sync(phone)
        pad.tutorial.setActive(true, slot: 1)
        _ = cloud.sync(pad)
        #expect(pad.summary(slot: 1)?.airlineName == "Guide Air" && !pad.tutorial.isActive(slot: 1))
        phone.tutorial.setActive(true, slot: 1)
        phone.delete(slot: 1)
        #expect(!phone.tutorial.isActive(slot: 1))
    }

    @Test func anOpenGameIsNeverReplacedByASync() throws {
        let cloud = FakeCloud()
        let phone = SaveSyncTests.device("phone")
        let pad = SaveSyncTests.device("pad")
        try phone.save(try SaveSyncTests.world("Open Air"), slot: 1)
        _ = cloud.sync(phone)
        _ = cloud.sync(pad)
        let onPad = try SaveSyncTests.play(pad, slot: 1)
        _ = cloud.sync(pad)
        let open = try phone.open(slot: 1)
        let report = cloud.sync(phone)
        #expect(try phone.load(slot: 1).clock == open.clock, "the slot keeps the open game")
        #expect(report.notes.count == 1 && report.notes[0].contains("another device"), "\(report.notes)")
        phone.closeGame()
        _ = cloud.sync(phone)
        #expect(try phone.load(slot: 1).clock == onPad.clock, "closed, the newer copy comes in")
    }

    @Test func aSaveSaysWhetherTheClockWasRunning() throws {
        let store = SaveSyncTests.device("phone")
        let w = try SaveSyncTests.world("Clock Air")
        try store.save(w, slot: 1)
        #expect(store.summary(slot: 1)?.clockRunning == nil, "a save that is not told says nothing")
        try store.save(w, slot: 1, clockRunning: true)
        #expect(store.summary(slot: 1)?.clockRunning == true)
        store.noteClock(running: false)
        try store.save(w, slot: 1)
        #expect(store.summary(slot: 1)?.clockRunning == false, "the app's last word on the clock fills in")
        #expect(store.onIO { store.lockedVersions(slot: 1) } == ["phone": 3], "each save counts once for this device")
    }
}
