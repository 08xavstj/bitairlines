import SwiftUI

// MARK: - Shapes

/// A rectangle with stepped (two-pixel) corners, the 8-bit panel outline. `step` is the size of one "pixel" of the corner.
struct PixelShape: InsettableShape {
    var step: CGFloat = 2
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let p = step, x0 = r.minX, y0 = r.minY, x1 = r.maxX, y1 = r.maxY
        var path = Path()
        path.move(to: CGPoint(x: x0 + 2 * p, y: y0))
        path.addLine(to: CGPoint(x: x1 - 2 * p, y: y0))
        path.addLine(to: CGPoint(x: x1 - 2 * p, y: y0 + p)); path.addLine(to: CGPoint(x: x1 - p, y: y0 + p))
        path.addLine(to: CGPoint(x: x1 - p, y: y0 + 2 * p)); path.addLine(to: CGPoint(x: x1, y: y0 + 2 * p))
        path.addLine(to: CGPoint(x: x1, y: y1 - 2 * p))
        path.addLine(to: CGPoint(x: x1 - p, y: y1 - 2 * p)); path.addLine(to: CGPoint(x: x1 - p, y: y1 - p))
        path.addLine(to: CGPoint(x: x1 - 2 * p, y: y1 - p)); path.addLine(to: CGPoint(x: x1 - 2 * p, y: y1))
        path.addLine(to: CGPoint(x: x0 + 2 * p, y: y1))
        path.addLine(to: CGPoint(x: x0 + 2 * p, y: y1 - p)); path.addLine(to: CGPoint(x: x0 + p, y: y1 - p))
        path.addLine(to: CGPoint(x: x0 + p, y: y1 - 2 * p)); path.addLine(to: CGPoint(x: x0, y: y1 - 2 * p))
        path.addLine(to: CGPoint(x: x0, y: y0 + 2 * p))
        path.addLine(to: CGPoint(x: x0 + p, y: y0 + 2 * p)); path.addLine(to: CGPoint(x: x0 + p, y: y0 + p))
        path.addLine(to: CGPoint(x: x0 + 2 * p, y: y0 + p))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> PixelShape { var copy = self; copy.inset += amount; return copy }
}

/// A filled panel: hard drop shadow, border.
struct PixelPanel: View {
    var fill: Color = Theme.surface
    var border: Color = Theme.panelBorder
    var step: CGFloat = 2
    var shadow = true
    var body: some View {
        ZStack {
            if shadow { PixelShape(step: step).fill(Theme.shadow).offset(x: 0, y: step * 1.5) }
            PixelShape(step: step).fill(fill)
            PixelShape(step: step).inset(by: step / 2).stroke(border, lineWidth: step)
        }
        .padding(.bottom, shadow ? step * 1.5 : 0)
    }
}

// MARK: - Pixel icons

/// 12 x 12 pixel icons (one colour, drawn in the current foreground style).
enum PixelIcon: String, CaseIterable {
    case map, fleet, routes, hangar, money, inbox, flag, settings, jobs, base
    case play, pause, forward, plus, minus, close, check, lock, star, back, next, help, alert, cargo, person, clock, trash

    var rows: [String] {
        switch self {
        case .map: ["....####....", "..##.##.##..", ".#..#..#..#.", ".#..#..#..#.", "############", ".#..#..#..#.", ".#..#..#..#.", "..##.##.##..", "....####....", "............", "............", "............"]
        case .fleet: [".....##.....", ".....##.....", "....####....", "....####....", "############", "############", ".....##.....", ".....##.....", "....####....", "...######...", "............", "............"]
        case .routes: ["##..........", "###.........", ".###........", "..###.......", "...###......", "....###.....", ".....###....", "......###...", ".......###..", "........###.", ".........###", "..........##"]
        case .hangar: ["....####....", "..########..", ".##########.", "############", "##........##", "##........##", "##........##", "##........##", "##........##", "##........##", "############", "............"]
        case .money: ["...######...", "..#......#..", ".#...##...#.", ".#..####..#.", ".#..##....#.", ".#...###..#.", ".#....##..#.", ".#..####..#.", ".#...##...#.", "..#......#..", "...######...", "............"]
        case .inbox: ["............", "############", "##........##", "#.##....##.#", "#..##..##..#", "#...####...#", "#....##....#", "#..........#", "#..........#", "############", "............", "............"]
        case .flag: ["##########..", "###########.", "############", "###########.", "##########..", "##..........", "##..........", "##..........", "##..........", "##..........", "##..........", "##.........."]
        case .jobs: ["...######...", "..#......#..", ".##########.", ".#........#.", ".#.######.#.", ".#........#.", ".#.######.#.", ".#........#.", ".#.####...#.", ".#........#.", ".##########.", "............"]
        case .base: ["..########..", "..#.#..#.#..", "..########..", "....####....", "....####....", "....####....", "....####....", "..########..", ".##########.", ".##..##..##.", "############", "............"]
        case .settings: ["....####....", ".#.######.#.", "..########..", "###..##..###", "###.####.###", "###.####.###", "###..##..###", "..########..", ".#.######.#.", "....####....", "............", "............"]
        case .play: ["..##........", "..####......", "..######....", "..########..", "..##########", "..##########", "..########..", "..######....", "..####......", "..##........", "............", "............"]
        case .pause: ["............", "..###..###..", "..###..###..", "..###..###..", "..###..###..", "..###..###..", "..###..###..", "..###..###..", "..###..###..", "............", "............", "............"]
        case .forward: ["............", ".##....##...", ".###...###..", ".####..####.", ".#####.#####", ".######.####", ".#####.#####", ".####..####.", ".###...###..", ".##....##...", "............", "............"]
        case .plus: ["............", ".....##.....", ".....##.....", ".....##.....", ".##########.", ".##########.", ".....##.....", ".....##.....", ".....##.....", "............", "............", "............"]
        case .minus: ["............", "............", "............", "............", ".##########.", ".##########.", "............", "............", "............", "............", "............", "............"]
        case .close: ["............", ".##......##.", "..##....##..", "...##..##...", "....####....", ".....##.....", "....####....", "...##..##...", "..##....##..", ".##......##.", "............", "............"]
        case .check: ["............", "..........##", ".........###", "........###.", "##.....###..", "###...###...", ".#######....", "..#####.....", "...###......", "............", "............", "............"]
        case .lock: ["...####.....", "..##..##....", "..#....#....", "..#....#....", ".########...", ".########...", ".###..###...", ".###..###...", ".####.###...", ".########...", "............", "............"]
        case .star: [".....##.....", ".....##.....", "....####....", "############", ".##########.", "..########..", "..########..", ".####..####.", ".###....###.", ".#........#.", "............", "............"]
        case .back: ["....##......", "...###......", "..####......", ".#####......", "######......", ".#####......", "..####......", "...###......", "....##......", "............", "............", "............"]
        case .next: ["......##....", ".......###..", "........###.", ".........###", "........####", ".........###", "........###.", ".......###..", "......##....", "............", "............", "............"]
        case .help: ["...#####....", "..#######...", "..##...##...", ".......##...", "......##....", ".....##.....", ".....##.....", "............", ".....##.....", ".....##.....", "............", "............"]
        case .alert: [".....##.....", ".....##.....", "....####....", "....####....", "...##..##...", "...##..##...", "..###..###..", "..###..###..", ".####..####.", ".##########.", "############", "............"]
        case .cargo: ["............", "############", "#..........#", "############", "#.#......#.#", "#.#......#.#", "#.#......#.#", "#.#......#.#", "#.#......#.#", "############", "............", "............"]
        case .person: ["....####....", "...######...", "...######...", "...######...", "....####....", "..########..", ".##########.", ".##########.", ".##########.", ".##########.", "............", "............"]
        case .clock: ["...######...", "..#......#..", ".#...##...#.", ".#...##...#.", ".#...##...#.", ".#...####.#.", ".#........#.", ".#........#.", "..#......#..", "...######...", "............", "............"]
        case .trash: ["....####....", "############", "............", "..########..", "..#.#..#.#..", "..#.#..#.#..", "..#.#..#.#..", "..#.#..#.#..", "..#.#..#.#..", "..########..", "............", "............"]
        }
    }
}

struct PixelIconView: View {
    let icon: PixelIcon
    /// Screen points per icon pixel.
    var pixel: CGFloat = 2
    var body: some View {
        let rows = icon.rows
        Canvas { context, _ in
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" {
                    context.fill(Path(CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: pixel, height: pixel)), with: .foreground, style: FillStyle(antialiased: false))
                }
            }
        }
        .frame(width: 12 * pixel, height: 12 * pixel)
        .accessibilityHidden(true)
    }
}

// MARK: - Backdrop

/// The night-sky wall with a faint dither, so flat colour never looks like a modern flat UI.
struct PixelBackdrop: View {
    var body: some View {
        ZStack {
            Theme.background
            Canvas { context, size in
                let cell: CGFloat = 4
                var y: CGFloat = 0
                var row = 0
                while y < size.height {
                    var x: CGFloat = row % 2 == 0 ? 0 : cell
                    while x < size.width {
                        context.fill(Path(CGRect(x: x, y: y, width: cell / 2, height: cell / 2)), with: .color(Color.white.opacity(0.018)), style: FillStyle(antialiased: false))
                        x += cell * 2
                    }
                    y += cell
                    row += 1
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Optional CRT scanlines over the whole screen (a setting).
struct ScanlineOverlay: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color.black.opacity(0.16)), style: FillStyle(antialiased: false))
                y += 3
            }
        }
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
