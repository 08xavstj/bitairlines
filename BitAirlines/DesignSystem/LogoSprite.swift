import SwiftUI

/// Any palette-indexed pixel picture (rows of characters, `.` is empty). Rows are folded into horizontal runs once, so drawing is cheap.
struct PixelArt: Equatable {
    struct Run: Equatable { let x: Int; let y: Int; let length: Int; let color: Int }

    let rows: [String]
    let palette: [Character: UInt32]
    let colors: [UInt32]
    let runs: [Run]
    let width: Int
    let height: Int

    init(rows: [String], palette: [Character: UInt32]) {
        self.rows = rows; self.palette = palette
        let keys = palette.keys.sorted()
        colors = keys.map { palette[$0]! }
        let index = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($0.element, $0.offset) })
        var runs: [Run] = []
        for (y, row) in rows.enumerated() {
            let cells = Array(row)
            var x = 0
            while x < cells.count {
                guard cells[x] != ".", let color = index[cells[x]] else { x += 1; continue }
                var end = x + 1
                while end < cells.count, cells[end] == cells[x] { end += 1 }
                runs.append(Run(x: x, y: y, length: end - x, color: color))
                x = end
            }
        }
        self.runs = runs
        width = rows.map(\.count).max() ?? 0
        height = rows.count
    }

    /// The first `count` rows, trimmed to the columns that have anything in them.
    func top(rows count: Int) -> PixelArt {
        let kept = Array(rows.prefix(count))
        let used = kept.flatMap { row in row.enumerated().filter { $0.element != "." }.map(\.offset) }
        guard let first = used.min(), let last = used.max() else { return PixelArt(rows: kept, palette: palette) }
        return PixelArt(rows: kept.map { String(Array($0)[first...last]) }, palette: palette)
    }

    var inkCount: Int { runs.reduce(0) { $0 + $1.length } }
}

struct PixelArtView: View {
    let art: PixelArt
    /// Screen points per art pixel across.
    var pixel: CGFloat = 3
    /// Height of one art pixel as a multiple of its width (the studio logo's pixels are a little taller than wide).
    var aspect: CGFloat = 1
    /// 0...1: how much of the picture has appeared (pixels dissolve in at random, like a retro fade).
    var reveal: Double = 1
    @MainActor var scale: CGFloat { Platform.screenScale }

    var body: some View {
        canvasBody
    }

    @ViewBuilder private var canvasBody: some View {
        let pw = pixel, ph = pixel * aspect, s = scale
        let edge = { (n: Int, unit: CGFloat) -> CGFloat in (CGFloat(n) * unit * s).rounded() / s }   // edges land on whole device pixels: no seams
        Canvas { context, _ in
            var paths = [Path](repeating: Path(), count: art.colors.count)
            func add(_ color: Int, _ x0: Int, _ x1: Int, _ y: Int) {
                paths[color].addRect(CGRect(x: edge(x0, pw), y: edge(y, ph), width: edge(x1, pw) - edge(x0, pw), height: edge(y + 1, ph) - edge(y, ph)))
            }
            for run in art.runs {
                if reveal >= 1 { add(run.color, run.x, run.x + run.length, run.y); continue }
                var start: Int?
                for dx in 0..<run.length {
                    if Self.order(run.x + dx, run.y) < reveal { if start == nil { start = dx } }
                    else if let begun = start { add(run.color, run.x + begun, run.x + dx, run.y); start = nil }
                }
                if let begun = start { add(run.color, run.x + begun, run.x + run.length, run.y) }
            }
            for (i, path) in paths.enumerated() { context.fill(path, with: .color(Color(hex: art.colors[i])), style: FillStyle(antialiased: false)) }
        }
        .frame(width: edge(art.width, pw), height: edge(art.height, ph))
        .accessibilityHidden(true)
    }

    /// A stable pseudo-random value in 0..<1 for a pixel (for the dissolve).
    static func order(_ x: Int, _ y: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: x &* 73856093 ^ y &* 19349663) &* 0x9E37_79B9_7F4A_7C15
        h ^= h >> 29
        return Double(h % 10_000) / 10_000
    }
}

/// The Lontra Industries logo: a pixel-art otter with the studio's name under it (`LogoSpriteData.swift`, copied from Ring Legacy).
enum LogoSprite {
    /// Otter and wordmark. Draw with `aspect: 1.25`.
    static let studio = PixelArt(rows: studioRows, palette: studioPalette)
    /// Just the otter (the rows above the wordmark's gap).
    static let otter = studio.top(rows: otterRows)
    /// The otter occupies the rows above this one; the blank row after it separates it from the name.
    static let otterRows = 112
    /// Draw both with this pixel aspect.
    static let aspect: CGFloat = 1.25
}
