import Testing
@testable import CoreSim

@Suite struct SeededRandomTests {
    @Test func sameSeedGivesSameStream() {
        var a = SeededRandom(seed: 42), b = SeededRandom(seed: 42)
        for _ in 0..<100 { #expect(a.next() == b.next()) }
    }

    @Test func goldenValuesNeverChange() {
        var r = SeededRandom(seed: 1)
        #expect(r.next() == 0x910A_2DEC_8902_5CC1)
    }

    @Test func unitStaysInRange() {
        var r = SeededRandom(seed: 7)
        for _ in 0..<1000 { let u = r.unit(); #expect(u >= 0 && u < 1) }
    }

    @Test func stateCanBeSavedAndResumed() {
        var a = SeededRandom(seed: 99)
        _ = a.next(); _ = a.next()
        var b = SeededRandom(state: a.currentState)
        #expect(a.next() == b.next())
    }

    @Test func intRespectsBounds() {
        var r = SeededRandom(seed: 3)
        for _ in 0..<1000 { let n = r.int(5...9); #expect(n >= 5 && n <= 9) }
    }
}
