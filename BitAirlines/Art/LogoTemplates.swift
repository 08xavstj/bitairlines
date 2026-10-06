import CoreCatalog
import CoreWorld

/// Starter emblems for the logo editor. Letters stand for the airline's colours: a primary, b secondary, c accent, w white.
struct LogoTemplate: Identifiable {
    let id: String
    let name: String
    let rows: [String]

    func logo(for b: Branding) -> [UInt8] {
        let map: [Character: Int] = ["a": b.primary, "b": b.secondary, "c": b.accent, "w": PixelPalette.white]
        var out = Branding.blankLogo()
        for (y, row) in rows.prefix(Branding.logoSize).enumerated() {
            for (x, ch) in row.prefix(Branding.logoSize).enumerated() {
                if let colour = map[ch] { out[y * Branding.logoSize + x] = UInt8(colour) }
            }
        }
        return out
    }
}

enum LogoTemplates {
    static let all: [LogoTemplate] = [
        LogoTemplate(id: "wing", name: "Wing", rows: [
            "................", "................", "..............aa", "............aaaa", "..........aaaaaa", ".......aaaaaaaaa", "....aaaaaaaaaaa.", "..aaaaaaaaaaa...",
            ".aaaaaaaaaa.....", "aaaaaaaa........", "aaaaaa..........", "aaaa............", "...bbbbbbbbbb...", "..bbbbbbbbbb....", "................", "................",
        ]),
        LogoTemplate(id: "star", name: "Star", rows: [
            "................", ".......aa.......", ".......aa.......", "......aaaa......", "......aaaa......", "aaaaaaaaaaaaaaaa", ".aaaaaaaaaaaaaa.", "..aaaaaaaaaaaa..",
            "...aaaaaaaaaa...", "....aaaaaaaa....", "....aaaaaaaa....", "...aaaa..aaaa...", "...aaa....aaa...", "..aaa......aaa..", "..aa........aa..", "................",
        ]),
        LogoTemplate(id: "peak", name: "Peak", rows: [
            "................", "..........cc....", ".........cccc...", "..........cc....", "................", ".......a........", "......aaa.......", ".....aaaaa..a...",
            "....aaaaaaa.aa..", "...aaaaaaaaaaaa.", "..aaaaaaaaaaaaa.", ".aaaaaaaaaaaaaaa", "aaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbb", "................", "................",
        ]),
        LogoTemplate(id: "sun", name: "Sun", rows: [
            ".......aa.......", ".......aa.......", "..a....aa....a..", "...a.aaaaaa.a...", "....aaaaaaaa....", ".....aaaaaa.....", "aa.aaaaaaaaaa.aa", "aa.aaaaaaaaaa.aa",
            ".....aaaaaa.....", "....aaaaaaaa....", "...a.aaaaaa.a...", "..a....aa....a..", ".......aa.......", ".......aa.......", "................", "................",
        ]),
        LogoTemplate(id: "ring", name: "Ring", rows: [
            "................", "....aaaaaaaa....", "..aaaaaaaaaaaa..", ".aaaa......aaaa.", ".aaa........aaa.", "aaa....cc....aaa", "aaa...cccc...aaa", "aaa...cccc...aaa",
            "aaa....cc....aaa", ".aaa........aaa.", ".aaaa......aaaa.", "..aaaaaaaaaaaa..", "....aaaaaaaa....", "................", "................", "................",
        ]),
        LogoTemplate(id: "arrow", name: "Arrow", rows: [
            "................", ".......aa.......", "......aaaa......", ".....aaaaaa.....", "....aaaaaaaa....", "...aaaaaaaaaa...", "..aaaa.aa.aaaa..", ".aaa...aa...aaa.",
            "aa.....aa.....aa", "......bbbb......", "......bbbb......", "......bbbb......", "......bbbb......", "................", "................", "................",
        ]),
    ]
}
