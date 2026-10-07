import Foundation
import Testing
import CoreCatalog
@testable import CoreWorld

/// A save is the World encoded as JSON (the app wraps it in a small envelope). These tests keep saves readable both ways: a world
/// round-trips without loss, an older save without the newest optional fields still loads and runs, and one kind of news from a
/// newer version of the game does not make a whole save unreadable on a device that has not updated yet.
@Suite struct SaveCompatibilityTests {
    static func decode(_ data: Data) throws -> World { try JSONDecoder().decode(World.self, from: data) }

    @Test func aWorldRoundTripsThroughJSONWithoutLoss() throws {
        var w = try Fixtures.flyingWorld()
        w.advance(byMinutes: 3 * 1440)
        let data = try Fixtures.encode(w)
        let back = try SaveCompatibilityTests.decode(data)
        #expect(back.clock == w.clock && back.airline == w.airline && back.aircraft == w.aircraft && back.routes == w.routes)
        #expect(back.news == w.news && back.issues == w.issues && back.books == w.books)
        #expect(try Fixtures.encode(back) == data, "encoding the decoded world gives the same bytes, so nothing is lost on the way")
    }

    /// An older save: the same world with every optional field added since the first version removed (the backing fields all end
    /// in Store, plus an aircraft's restoration), as a save from before those systems would look.
    @Test func anOlderSaveWithoutTheNewestFieldsStillLoadsAndRuns() throws {
        var w = try Fixtures.flyingWorld()
        w.advance(byMinutes: 2 * 1440)
        let object = try JSONSerialization.jsonObject(with: Fixtures.encode(w))
        let json = try #require(SaveCompatibilityTests.withoutNewestFields(object) as? [String: Any])
        #expect(json["operationsStore"] == nil)
        let data = try JSONSerialization.data(withJSONObject: json)
        var old = try SaveCompatibilityTests.decode(data)
        #expect(old.clock == w.clock && old.airline.cash == w.airline.cash && old.aircraft.count == w.aircraft.count && old.routes.count == w.routes.count)
        #expect(old.operationsStore == nil, "the systems added later are missing, and read as in a new game")
        #expect(old.ops.pilots.isEmpty && old.routes[0].service == Route().service)
        let minute = old.clock.minute
        old.advance(byMinutes: 1440)
        #expect(old.clock.minute == minute + 1440, "a day runs on the older save")
        #expect(old.operationsStore != nil, "and the first change gives it the newer systems")
    }

    /// Removes every key ending in "Store" (the optional backing fields with a computed facade) and "restoration", at any depth.
    static func withoutNewestFields(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, inner) in dict where !key.hasSuffix("Store") && key != "restoration" { out[key] = withoutNewestFields(inner) }
            return out
        }
        if let list = value as? [Any] { return list.map(withoutNewestFields) }
        return value
    }

    @Test func aNewsKindFromANewerVersionReadsAsAMilestone() throws {
        let item = try JSONDecoder().decode(NewsItem.self, from: Data(#"{"minute":5,"kind":"somethingNew","subject":"C-FXYZ","amount":3}"#.utf8))
        #expect(item.kind == .milestone && item.minute == 5 && item.subject == "C-FXYZ" && item.amount == 3)
        let known = try JSONDecoder().decode(NewsItem.self, from: Data(#"{"minute":1,"kind":"breakdown","subject":"x","amount":0}"#.utf8))
        #expect(known.kind == .breakdown, "known kinds are untouched")
        // A whole save with such an item loads, and the item is still there.
        var w = try Fixtures.world()
        w.addNews(.routeOpened, subject: "YEV-YUB")
        let text = try #require(String(data: Fixtures.encode(w), encoding: .utf8))
        let future = text.replacingOccurrences(of: "\"kind\":\"routeOpened\"", with: "\"kind\":\"fromTheFuture\"")
        #expect(future != text)
        let back = try SaveCompatibilityTests.decode(Data(future.utf8))
        #expect(back.news.count == w.news.count && back.news.last?.kind == .milestone && back.news.last?.subject == "YEV-YUB")
    }

    /// Game rules stay strict: an unknown value in a stored enum other than news is an error, not a guess.
    @Test func gameRuleEnumsStayStrict() {
        #expect(throws: (any Error).self) { try JSONDecoder().decode([String: PausePolicy].self, from: Data(#"{"p":"sometimes"}"#.utf8)) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode([String: IssueChoice].self, from: Data(#"{"c":"ignoreIt"}"#.utf8)) }
    }
}
