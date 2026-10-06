// CoreWorld/Lookahead.swift: the simulation is deterministic, so a copy of the world run forward shows exactly what will happen next.
// The app uses it when the player leaves: it runs a copy forward with the same rules as the "while you were away" catch-up and
// schedules one reminder for the first thing that will need the player. The world itself is never changed.

/// Something ahead that will need the player. Codes and numbers only; the app writes the words.
public enum LookaheadKind: Sendable, Hashable {
    /// An aircraft will break down on the ground.
    case breakdown(aircraftID: Int)
    /// The bank balance will go past the overdraft limit.
    case overdraft
    case bankruptcy
    /// A job already taken will not land by its deadline.
    case jobLate(jobID: Int)
    /// Another issue will stop the clock (with the pause policy set to stop for everything).
    case stopped
    /// Nothing needs the player before the look-ahead ends (the away limit is reached).
    case limitReached
}

public struct LookaheadEvent: Sendable, Hashable {
    public var kind: LookaheadKind
    /// Game minutes from now.
    public var minutesAhead: Int

    public init(kind: LookaheadKind, minutesAhead: Int) {
        self.kind = kind
        self.minutesAhead = minutesAhead
    }
}

extension Tuning {
    /// The copy is run forward in steps of this many game minutes, checking for news after each.
    public static let lookaheadStepMinutes = 30
    /// A job that will be late is announced this many game minutes before its deadline.
    public static let lookaheadJobWarningMinutes = 120
}

extension World {
    /// Runs a copy of the world forward for up to `limit` game minutes and returns the first thing that will need the player:
    /// a breakdown, an overdraft, a late job, or else the end of the look-ahead. Nil when the game is over, something already
    /// waits for the player, or `limit` is not positive.
    public func firstEventNeedingPlayer(within limit: Int) -> LookaheadEvent? {
        guard limit > 0, !isBankrupt, !isPausedByIssue else { return nil }
        let start = clock.minute
        let end = start + limit
        let firstNewIssue = nextIssueID
        var copy = self
        while copy.clock.minute < end {
            let result = copy.advance(toMinute: min(end, copy.clock.minute + Tuning.lookaheadStepMinutes))
            if let found = copy.firstNeed(sinceIssue: firstNewIssue, start: start) {
                return LookaheadEvent(kind: found.kind, minutesAhead: max(0, found.minute - start))
            }
            if result != .reachedTarget {
                return LookaheadEvent(kind: .stopped, minutesAhead: max(0, copy.clock.minute - start))
            }
        }
        return LookaheadEvent(kind: .limitReached, minutesAhead: limit)
    }

    /// The earliest need found so far in a world being run forward: a new critical issue, or a taken job past its deadline.
    func firstNeed(sinceIssue firstNewIssue: Int, start: Int) -> (minute: Int, kind: LookaheadKind)? {
        var found: [(minute: Int, kind: LookaheadKind)] = []
        for issue in issues where issue.id >= firstNewIssue {
            switch issue.kind {
            case .breakdown(let planeID): found.append((minute: issue.raisedMinute, kind: .breakdown(aircraftID: planeID)))
            case .overdraft: found.append((minute: issue.raisedMinute, kind: .overdraft))
            case .bankruptcy: found.append((minute: issue.raisedMinute, kind: .bankruptcy))
            default: break
            }
        }
        // A job still on the board after its deadline will land late. Jobs already late when the player left are not news.
        for job in ops.jobs where job.isTaken && job.deadlineMinute > start && job.deadlineMinute <= clock.minute {
            found.append((minute: max(start, job.deadlineMinute - Tuning.lookaheadJobWarningMinutes), kind: .jobLate(jobID: job.id)))
        }
        var best: (minute: Int, kind: LookaheadKind)?
        for item in found where best == nil || item.minute < best!.minute { best = item }
        return best
    }
}
