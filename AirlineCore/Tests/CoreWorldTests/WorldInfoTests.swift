import Testing
@testable import CoreWorld

@Suite struct WorldInfoTests {
    @Test func rulesVersionIsSet() { #expect(WorldInfo.rulesVersion >= 1) }
}
