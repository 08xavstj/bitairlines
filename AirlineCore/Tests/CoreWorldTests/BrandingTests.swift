import Foundation
import Testing
import CoreCatalog
@testable import CoreWorld

@Suite struct BrandingTests {
    @Test func theCanvasIs24Square() {
        #expect(Branding.logoSize == 24)
        #expect(Branding.starter.logo.count == 24 * 24)
        #expect(Branding.starter.logo.contains { $0 != 0 })
    }

    @Test func anOldSixteenSquareLogoLoadsCentred() throws {
        var old = [UInt8](repeating: 0, count: 16 * 16)
        old[0] = UInt8(PixelPalette.orange)
        old[15 * 16 + 15] = UInt8(PixelPalette.sky)
        let json = "{\"primary\":1,\"secondary\":2,\"accent\":3,\"style\":\"cheatline\",\"logo\":\(old.map(Int.init))}"
        let b = try JSONDecoder().decode(Branding.self, from: Data(json.utf8))
        #expect(b.logo.count == 24 * 24)
        #expect(b.logoPixel(x: 4, y: 4) == PixelPalette.orange)
        #expect(b.logoPixel(x: 19, y: 19) == PixelPalette.sky)
        #expect(b.logoPixel(x: 0, y: 0) == 0)
    }

    @Test func aBrandingSurvivesASaveAndLoad() throws {
        var b = Branding.starter
        b.setLogoPixel(x: 23, y: 23, colour: PixelPalette.orange)
        let back = try JSONDecoder().decode(Branding.self, from: JSONEncoder().encode(b))
        #expect(back == b)
    }
}
