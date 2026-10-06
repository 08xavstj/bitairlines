import Foundation

/// How two copies of the same game relate. Every save adds one to a count for the device that wrote it (`SaveEnvelope.versions`),
/// so a copy whose counts are all at least as high as another's was made from it. When each copy is ahead on a different device,
/// both were played since they last matched: a fork, and neither may replace the other.
enum SaveLineage: Equatable {
    /// The same save.
    case same
    /// The first copy was made from the second one and has moved on.
    case ahead
    /// The second copy was made from the first one and has moved on.
    case behind
    /// Both moved on since they last matched.
    case forked

    static func compare(_ a: [String: Int], _ b: [String: Int]) -> SaveLineage {
        var aAhead = false
        var bAhead = false
        for device in Set(a.keys).union(b.keys) {
            let x = a[device] ?? 0
            let y = b[device] ?? 0
            if x > y { aAhead = true }
            if y > x { bAhead = true }
        }
        switch (aAhead, bAhead) {
        case (false, false): return .same
        case (true, false): return .ahead
        case (false, true): return .behind
        case (true, true): return .forked
        }
    }

    /// Compares two saves of one game. A save from before the counts has none; then the game clock decides, as it always did
    /// (the copy further along wins, and a fork cannot be seen).
    static func compare(_ a: SaveStamp, _ b: SaveStamp) -> SaveLineage {
        if let x = a.versions, let y = b.versions { return compare(x, y) }
        let x = a.progress ?? 0
        let y = b.progress ?? 0
        if x == y { return .same }
        return x > y ? .ahead : .behind
    }

    /// True when `mine` may be written over `theirs` in iCloud: it was made from it. Never over a copy that moved on elsewhere.
    static func mayReplace(_ theirs: SaveStamp, with mine: SaveStamp) -> Bool {
        switch compare(mine, theirs) {
        case .ahead: return true
        // Older saves: the same game clock, but the player may have changed things while paused.
        case .same: return mine.versions == nil || theirs.versions == nil
        case .behind, .forked: return false
        }
    }
}
