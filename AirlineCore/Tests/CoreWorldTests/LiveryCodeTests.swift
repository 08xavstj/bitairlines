import Testing
import CoreCatalog
@testable import CoreWorld

/// The livery code: an airline's colours, paint scheme and logo as a short text other players paste in.
@Suite struct LiveryCodeTests {
    /// A code with a correct checksum from raw symbols (to test what the decoder does with a well-formed but wrong code).
    func code(_ symbols: [Int]) -> String {
        let sum = LiveryCode.checksum(symbols)
        return LiveryCode.prefix + String((symbols + [sum / 32, sum % 32]).map { LiveryCode.alphabet[$0] })
    }

    /// Runs for an empty 24 x 24 logo: 18 runs of 32 transparent pixels.
    var blankRuns: [Int] { Array(repeating: [0, 31], count: 18).flatMap { $0 } }

    @Test func theStarterLookSurvivesARoundTrip() throws {
        let text = LiveryCode.encode(.starter)
        #expect(text.hasPrefix(LiveryCode.prefix))
        #expect(text.allSatisfy { $0.isASCII && !$0.isWhitespace })
        let back = try LiveryCode.decode(text)
        #expect(back == Branding.starter)
    }

    @Test func aBusyLogoAndEveryColourSurviveARoundTrip() throws {
        var logo: [UInt8] = []
        for i in 0..<(Branding.logoSize * Branding.logoSize) { logo.append(UInt8((i * 7 + i / 24) % PixelPalette.count)) }
        let busy = Branding(primary: PixelPalette.count - 1, secondary: 1, accent: 17, style: .splitBody, logo: logo)
        let back = try LiveryCode.decode(LiveryCode.encode(busy))
        #expect(back == busy)

        for style in LiveryStyle.allCases {
            var b = Branding.starter
            b.style = style
            let again = try LiveryCode.decode(LiveryCode.encode(b))
            #expect(again.style == style)
        }
    }

    @Test func pastingIsForgiving() throws {
        let text = LiveryCode.encode(.starter)
        let lower = try LiveryCode.decode(text.lowercased())
        #expect(lower == Branding.starter)
        let head = String(text.prefix(20))
        let tail = String(text.dropFirst(20))
        let spaced = try LiveryCode.decode("  " + head + " \n" + tail + " ")
        #expect(spaced == Branding.starter)
        let body = String(text.dropFirst(LiveryCode.prefix.count).map { $0 == "0" ? "O" : ($0 == "1" ? "I" : $0) })
        let misread = try LiveryCode.decode(LiveryCode.prefix + body)
        #expect(misread == Branding.starter)
    }

    @Test func badCodesAreRefused() throws {
        #expect(throws: LiveryCodeError.wrongPrefix) { try LiveryCode.decode("") }
        #expect(throws: LiveryCodeError.wrongPrefix) { try LiveryCode.decode("HELLO-16NA00Z0") }
        #expect(throws: LiveryCodeError.badCharacter) { try LiveryCode.decode(LiveryCode.prefix + "16NAU0") }
        #expect(throws: LiveryCodeError.badCharacter) { try LiveryCode.decode(LiveryCode.prefix + "16NA*0") }
        #expect(throws: LiveryCodeError.tooShort) { try LiveryCode.decode(LiveryCode.prefix + "16NA") }

        // One symbol changed, or the end cut off: the checksum no longer matches.
        let text = Array(LiveryCode.encode(.starter))
        var typo = text
        let at = LiveryCode.prefix.count + 2
        typo[at] = typo[at] == "A" ? "B" : "A"
        #expect(throws: LiveryCodeError.badChecksum) { try LiveryCode.decode(String(typo)) }
        #expect(throws: (any Error).self) { try LiveryCode.decode(String(text.dropLast(3))) }

        // Well formed, but wrong inside.
        #expect(throws: LiveryCodeError.unknownVersion) { try LiveryCode.decode(code([2, 6, 21, 10, 0] + blankRuns)) }
        #expect(throws: LiveryCodeError.badColour) { try LiveryCode.decode(code([1, 0, 21, 10, 0] + blankRuns)) }
        #expect(throws: LiveryCodeError.badScheme) { try LiveryCode.decode(code([1, 6, 21, 10, LiveryStyle.allCases.count] + blankRuns)) }
        #expect(throws: LiveryCodeError.badLogo) { try LiveryCode.decode(code([1, 6, 21, 10, 0] + blankRuns.dropLast(2))) }
        #expect(throws: LiveryCodeError.badLogo) { try LiveryCode.decode(code([1, 6, 21, 10, 0] + blankRuns + [0, 0])) }
        #expect(throws: LiveryCodeError.badLogo) { try LiveryCode.decode(code([1, 6, 21, 10, 0] + blankRuns + [0])) }

        // The helper itself makes codes the decoder takes.
        let blank = try LiveryCode.decode(code([1, 6, 21, 10, 0] + blankRuns))
        #expect(blank.logo.allSatisfy { $0 == 0 } && blank.primary == 6)
    }
}
