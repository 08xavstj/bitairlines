import Testing
import CoreCatalog
@testable import CoreWorld

/// Running a copy of the world forward finds the first thing that will need the player, and the real world then does exactly that.
@Suite struct LookaheadTests {
    @Test func aQuietAirlineRunsToTheEndOfTheLookahead() throws {
        let w = try Fixtures.world()
        let event = w.firstEventNeedingPlayer(within: 2 * 1440)
        #expect(event == LookaheadEvent(kind: .limitReached, minutesAhead: 2 * 1440))
        #expect(w.clock.minute == 6 * 60, "the world itself does not move")
        #expect(w.firstEventNeedingPlayer(within: 0) == nil)
    }

    @Test func anOverdraftIsFoundAndHappensWhenPredicted() throws {
        var w = try Fixtures.world()
        w.airline.cash = -Tuning.overdraftLimit - 50_000
        let start = w.clock.minute
        let event = w.firstEventNeedingPlayer(within: 2 * 1440)
        // Money is checked at midnight.
        #expect(event == LookaheadEvent(kind: .overdraft, minutesAhead: 1440 - start))

        let result = w.advance(byMinutes: 2 * 1440)
        #expect(result == .pausedForIssue)
        #expect(w.clock.minute == 1440)
        let raised = w.issues.contains { if case .overdraft = $0.kind { return true } else { return false } }
        #expect(raised)
    }

    @Test func nothingIsLookedForWhileTheGameIsAlreadyStopped() throws {
        var w = try Fixtures.world()
        w.airline.cash = -Tuning.overdraftLimit - 50_000
        w.advance(byMinutes: 2 * 1440)
        #expect(w.isPausedByIssue)
        #expect(w.firstEventNeedingPlayer(within: 2 * 1440) == nil)
    }

    @Test func aJobThatCannotLandInTimeIsFound() throws {
        var w = try Fixtures.world()
        w.setPausePolicy(.never)
        let now = w.clock.minute
        // Ten minutes to fly a job to Tuktoyaktuk: no aircraft can do it.
        w.ops.jobs.append(Job(id: 901, kind: .medevac, from: "YEV", to: "YUB", passengers: 2, cargoKg: 0, pay: 5_000,
                              deadlineMinute: now + 10, expiresMinute: now + 5, aircraftID: nil, loaded: false))
        try w.takeJob(jobID: 901, aircraftID: w.aircraft[0].id)
        let event = w.firstEventNeedingPlayer(within: 2 * 1440)
        #expect(event?.kind == .jobLate(jobID: 901))
        #expect(event?.minutesAhead == 0, "the warning comes at once, since the deadline is under two hours away")
    }
}
