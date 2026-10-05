import Testing
@testable import BitAirlines

@Suite struct SmokeTests {
    @Test func pixelFontSnapsToCrispSizes() {
        #expect(PixelFont.snapped(14) == 13.333)
        #expect(PixelFont.snapped(30) == 32)
    }

    @Test func textSizeStepsNeverLeaveTheSizeList() {
        for step in 0...PixelFont.maxStep {
            #expect(PixelFont.sizes.contains(PixelFont.scaled(13.333, step: step)))
        }
    }
}
