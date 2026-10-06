import Testing
import Foundation
import CoreCatalog
import CoreWorld
@testable import BitAirlines

/// The app side of the first-session work: the next-step words, the away notes and when the rating prompt may come.
@Suite struct GrowthTests {
    func world() throws -> World {
        try World.newGame(NewGameConfig(airlineName: "Lontra Air", airlineCode: "LT", homeAirport: "YEV", branding: .starter,
                                        difficulty: .standard, starterTypeID: "c208", seed: 7))
    }

    @Test func nextStepLinesArePlainAndShort() throws {
        let w = try world()
        let lines = [
            NextStepWords.line(.openFirstRoute, world: w),
            NextStepWords.line(.saveForAircraft(typeID: "dhc6", price: 3_000_000, days: 9), world: w),
            NextStepWords.line(.levelNeedsReputation(level: 3, reputation: 20), world: w),
            NextStepWords.line(.openSecondRoute, world: w),
        ]
        #expect(lines[1] == "DHC-6 Twin Otter affordable in 9 days")
        #expect(lines[2] == "Level 3 needs reputation 20")
        #expect(lines[3] == "Open a second route")
        for line in lines {
            #expect(!line.contains("!") && line.count <= 60, "\(line)")
        }
    }

    @Test func awayTimeBecomesRealTimeAtTheAwayRate() {
        // One game hour for each real minute: three game days is 72 real minutes.
        #expect(AwayNotes.realSeconds(gameMinutes: AwayReport.maxGameMinutes) == 72 * 60)
        #expect(AwayNotes.realSeconds(gameMinutes: 60) == 60)
    }

    @Test func awayNotesHaveNoExclamationMarks() throws {
        let w = try world()
        let kinds: [LookaheadKind] = [.breakdown(aircraftID: w.aircraft[0].id), .overdraft, .bankruptcy, .jobLate(jobID: 1), .stopped, .limitReached]
        for kind in kinds {
            let words = AwayNotes.text(kind, world: w)
            #expect(!words.title.contains("!") && !words.body.contains("!"))
        }
        let note = try #require(AwayNotes.next(for: w))
        #expect(note.afterSeconds >= 60)
    }

    @Test func theRatingPromptFollowsAWinOnly() {
        let start = ReviewMoment(goalsCompleted: 0, level: 1, hasMedal: false)
        #expect(ReviewMoment.isWin(from: start, to: ReviewMoment(goalsCompleted: 1, level: 1, hasMedal: false)))
        #expect(ReviewMoment.isWin(from: start, to: ReviewMoment(goalsCompleted: 0, level: 2, hasMedal: false)))
        #expect(ReviewMoment.isWin(from: start, to: ReviewMoment(goalsCompleted: 0, level: 1, hasMedal: true)))
        #expect(!ReviewMoment.isWin(from: ReviewMoment(goalsCompleted: 3, level: 3, hasMedal: false), to: ReviewMoment(goalsCompleted: 4, level: 3, hasMedal: false)))
        #expect(!ReviewMoment.isWin(from: start, to: start))
    }

    @Test func theRatingPromptWaitsAfterABreakdownOrDebt() throws {
        var w = try world()
        #expect(ReviewMoment.isCalm(w))
        w.airline.cash = -1
        #expect(!ReviewMoment.isCalm(w))
    }

    @Test func theRatingPromptComesOncePerVersion() throws {
        let defaults = try #require(UserDefaults(suiteName: "GrowthTests.review"))
        defaults.removePersistentDomain(forName: "GrowthTests.review")
        let store = ReviewStore(defaults: defaults)
        #expect(!store.askedThisVersion("1.0"))
        store.markAsked("1.0")
        #expect(store.askedThisVersion("1.0"))
        #expect(!store.askedThisVersion("1.1"))
    }
}
