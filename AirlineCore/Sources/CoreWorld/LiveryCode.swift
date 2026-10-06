// CoreWorld/LiveryCode.swift: an airline's look as a short text code players can share and paste into the branding editor.
//
// Format: "BITAIR-" then base-32 symbols (Crockford's alphabet, 5 bits each, so one symbol holds one palette index):
//   version, primary, secondary, accent, paint scheme,
//   the 24 x 24 logo as runs (colour, run length - 1), row by row from the top left, runs of at most 32,
//   and a two-symbol checksum of everything before it.
// Decoding ignores case, spaces, line breaks and hyphens, and reads O as 0 and I or L as 1. Anything else wrong is refused.
import CoreCatalog

public enum LiveryCodeError: Error, Sendable, Hashable {
    case wrongPrefix
    case badCharacter
    case tooShort
    case badChecksum
    case unknownVersion
    case badColour
    case badScheme
    case badLogo
}

public enum LiveryCode {
    public static let prefix = "BITAIR-"
    static let version = 1
    static let alphabet: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let maxRun = 32
    /// Symbols before the logo runs.
    static let headerCount = 5
    static let checksumModulus = 1024
    /// Palette indexes a code can hold: one symbol each, so at most 32 (the palette has 32).
    static var colourLimit: Int { min(PixelPalette.count, alphabet.count) }

    public static func encode(_ branding: Branding) -> String {
        var symbols = [version, branding.primary, branding.secondary, branding.accent, styleIndex(branding.style)]
        let logo = branding.logo
        var i = 0
        while i < logo.count {
            let colour = Int(logo[i])
            var run = 1
            while i + run < logo.count && Int(logo[i + run]) == colour && run < maxRun { run += 1 }
            symbols.append(colour)
            symbols.append(run - 1)
            i += run
        }
        let sum = checksum(symbols)
        symbols.append(sum / 32)
        symbols.append(sum % 32)
        return prefix + String(symbols.map { alphabet[$0] })
    }

    public static func decode(_ text: String) throws -> Branding {
        var cleaned: [Character] = []
        for ch in text where !ignored(ch) { cleaned.append(ch) }
        let head: [Character] = Array("BITAIR")
        guard cleaned.count >= head.count, zip(cleaned.prefix(head.count), head).allSatisfy({ upper($0.0) == $0.1 }) else { throw LiveryCodeError.wrongPrefix }

        var symbols: [Int] = []
        for ch in cleaned.dropFirst(head.count) {
            guard let value = symbolValue(ch) else { throw LiveryCodeError.badCharacter }
            symbols.append(value)
        }
        guard symbols.count >= headerCount + 2 + 2 else { throw LiveryCodeError.tooShort }
        let body = Array(symbols.dropLast(2))
        guard symbols[symbols.count - 2] * 32 + symbols[symbols.count - 1] == checksum(body) else { throw LiveryCodeError.badChecksum }
        guard body[0] == version else { throw LiveryCodeError.unknownVersion }
        let colours = [body[1], body[2], body[3]]
        guard colours.allSatisfy({ $0 >= 1 && $0 < colourLimit }) else { throw LiveryCodeError.badColour }
        guard body[4] < LiveryStyle.allCases.count else { throw LiveryCodeError.badScheme }

        let runs = body.dropFirst(headerCount)
        guard runs.count % 2 == 0 else { throw LiveryCodeError.badLogo }
        let size = Branding.logoSize * Branding.logoSize
        var logo: [UInt8] = []
        logo.reserveCapacity(size)
        var k = runs.startIndex
        while k < runs.endIndex {
            let colour = runs[k]
            let length = runs[k + 1] + 1
            guard colour < colourLimit, logo.count + length <= size else { throw LiveryCodeError.badLogo }
            logo.append(contentsOf: [UInt8](repeating: UInt8(colour), count: length))
            k += 2
        }
        guard logo.count == size else { throw LiveryCodeError.badLogo }
        return Branding(primary: colours[0], secondary: colours[1], accent: colours[2], style: LiveryStyle.allCases[body[4]], logo: logo)
    }

    static func styleIndex(_ style: LiveryStyle) -> Int { LiveryStyle.allCases.firstIndex(of: style) ?? 0 }

    /// A small rolling sum over the symbols (10 bits, two symbols), so a typo or a cut-off paste is caught.
    static func checksum(_ symbols: [Int]) -> Int {
        var sum = 0
        for s in symbols { sum = (sum * 31 + s + 7) % checksumModulus }
        return sum
    }

    static func ignored(_ ch: Character) -> Bool { ch == " " || ch == "-" || ch == "\n" || ch == "\r" || ch == "\t" }

    static func upper(_ ch: Character) -> Character {
        guard let ascii = ch.asciiValue, ascii >= 97, ascii <= 122 else { return ch }
        return Character(Unicode.Scalar(ascii - 32))
    }

    static func symbolValue(_ ch: Character) -> Int? {
        let c = upper(ch)
        if c == "O" { return 0 }
        if c == "I" || c == "L" { return 1 }
        return alphabet.firstIndex(of: c)
    }
}
