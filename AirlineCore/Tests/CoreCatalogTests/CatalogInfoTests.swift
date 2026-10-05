import Testing
@testable import CoreCatalog

@Suite struct CatalogInfoTests {
    @Test func schemaVersionIsSet() { #expect(CatalogInfo.schemaVersion >= 1) }
}
