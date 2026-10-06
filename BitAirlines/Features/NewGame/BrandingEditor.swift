import SwiftUI
import CoreCatalog
import CoreWorld

/// Pick a colour from the game's 32-colour pixel palette.
struct PaletteGrid: View {
    @Binding var selection: Int
    var columns = 8
    var size: CGFloat = 24
    var includeNone = false

    var body: some View {
        let rows = rowIndexes()
        VStack(spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 2) {
                    ForEach(row, id: \.self) { index in swatch(index) }
                }
            }
        }
    }

    private func rowIndexes() -> [[Int]] {
        let first = includeNone ? 0 : 1
        let all = Array(first..<PixelPalette.count)
        return stride(from: 0, to: all.count, by: columns).map { Array(all[$0..<min($0 + columns, all.count)]) }
    }

    private func swatch(_ index: Int) -> some View {
        let selected = index == selection
        return Button { selection = index } label: {
            ZStack {
                if index == 0 {
                    Rectangle().fill(Theme.surfaceRaised)
                    PixelIconView(icon: .close, pixel: 1).foregroundStyle(Theme.textMuted)
                } else {
                    Rectangle().fill(Livery.color(index))
                }
            }
            .frame(width: size, height: size)
            .overlay(Rectangle().stroke(selected ? Theme.textPrimary : Theme.panelBorder, lineWidth: selected ? 3 : 1))
        }
        .buttonStyle(.tap)
        .accessibilityLabel("Colour \(index)")
        .accessibilitySelected(selected)
    }
}

enum LogoTool: String, CaseIterable, Identifiable {
    case pen, erase, fill
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pen: "Pen"
        case .erase: "Erase"
        case .fill: "Fill"
        }
    }
}

/// A 16 x 16 pixel editor for the airline logo.
struct LogoEditor: View {
    @Binding var branding: Branding
    @State private var tool: LogoTool = .pen
    @State private var color = PixelPalette.orange
    @State private var mirror = true
    @State private var undoStack: [[UInt8]] = []
    @State private var strokeStarted = false

    private let cell: CGFloat = 15

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 8) {
                grid
                HStack(spacing: 6) {
                    ForEach(LogoTool.allCases) { t in Chip(title: t.label, selected: tool == t) { tool = t } }
                }
                HStack(spacing: 6) {
                    Chip(title: "Mirror", selected: mirror) { mirror.toggle() }
                    Button("Undo") { undo() }.buttonStyle(.small).disabled(undoStack.isEmpty)
                    Button("Clear") { remember(); branding.logo = Branding.blankLogo() }.buttonStyle(.small)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Colour").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                PaletteGrid(selection: $color, columns: 8, size: 22)
                Text("Start from").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                templates
            }
        }
    }

    private var templates: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(stride(from: 0, to: LogoTemplates.all.count, by: 3)), id: \.self) { start in
                HStack(spacing: 6) {
                    ForEach(LogoTemplates.all[start..<min(start + 3, LogoTemplates.all.count)]) { template in
                        Button(template.name) { remember(); branding.logo = template.logo(for: branding) }.buttonStyle(.small)
                    }
                }
            }
        }
    }

    private var grid: some View {
        let side = cell * CGFloat(Branding.logoSize)
        return Canvas { context, _ in
            for y in 0..<Branding.logoSize {
                for x in 0..<Branding.logoSize {
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)
                    let p = branding.logoPixel(x: x, y: y)
                    let checker = (x + y) % 2 == 0
                    context.fill(Path(rect), with: .color(p > 0 ? Livery.color(p) : (checker ? Theme.surfaceRaised : Theme.surface)), style: FillStyle(antialiased: false))
                }
            }
            if mirror {
                context.fill(Path(CGRect(x: side / 2 - 1, y: 0, width: 2, height: side)), with: .color(Theme.accent.opacity(0.5)), style: FillStyle(antialiased: false))
            }
        }
        .frame(width: side, height: side)
        .overlay(Rectangle().stroke(Theme.panelBorder, lineWidth: 2))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let x = Int(drag.location.x / cell), y = Int(drag.location.y / cell)
                guard x >= 0, y >= 0, x < Branding.logoSize, y < Branding.logoSize else { return }
                if !strokeStarted { remember(); strokeStarted = true }
                apply(x: x, y: y)
            }
            .onEnded { _ in strokeStarted = false })
        .accessibilityLabel("Logo editor")
    }

    private func apply(x: Int, y: Int) {
        switch tool {
        case .pen:
            paint(x: x, y: y, colour: color)
        case .erase:
            paint(x: x, y: y, colour: 0)
        case .fill:
            if !fillDoneForThisStroke { flood(x: x, y: y, colour: color) }
        }
    }

    /// A fill acts once per touch, so dragging does not repaint.
    @State private var fillDoneForThisStroke = false

    private func paint(x: Int, y: Int, colour: Int) {
        branding.setLogoPixel(x: x, y: y, colour: colour)
        if mirror { branding.setLogoPixel(x: Branding.logoSize - 1 - x, y: y, colour: colour) }
    }

    private func flood(x: Int, y: Int, colour: Int) {
        fillDoneForThisStroke = true
        let target = branding.logoPixel(x: x, y: y)
        guard target != colour else { return }
        var queue = [(x, y)]
        var seen = Set<Int>()
        while let (cx, cy) = queue.popLast() {
            guard cx >= 0, cy >= 0, cx < Branding.logoSize, cy < Branding.logoSize else { continue }
            let key = cy * Branding.logoSize + cx
            guard !seen.contains(key), branding.logoPixel(x: cx, y: cy) == target else { continue }
            seen.insert(key)
            branding.setLogoPixel(x: cx, y: cy, colour: colour)
            queue.append((cx + 1, cy)); queue.append((cx - 1, cy)); queue.append((cx, cy + 1)); queue.append((cx, cy - 1))
        }
    }

    private func remember() {
        undoStack.append(branding.logo)
        if undoStack.count > 30 { undoStack.removeFirst() }
        fillDoneForThisStroke = false
    }

    private func undo() {
        guard let last = undoStack.popLast() else { return }
        branding.logo = last
    }
}

/// The airline's colours and paint scheme.
struct ColourEditor: View {
    @Binding var branding: Branding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            role("Main colour", \.primary)
            role("Stripe colour", \.secondary)
            role("Detail colour", \.accent)
            Text("Paint scheme").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(stride(from: 0, to: LiveryStyle.allCases.count, by: 3)), id: \.self) { start in
                    HStack(spacing: 6) {
                        ForEach(LiveryStyle.allCases[start..<min(start + 3, LiveryStyle.allCases.count)], id: \.self) { style in
                            Chip(title: Self.name(style), selected: branding.style == style) { branding.style = style }
                        }
                    }
                }
            }
        }
    }

    private func role(_ title: String, _ keyPath: WritableKeyPath<Branding, Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).pixelFont(10.667).foregroundStyle(Theme.textMuted)
            PaletteGrid(selection: Binding(get: { branding[keyPath: keyPath] }, set: { branding[keyPath: keyPath] = $0 }), columns: 16, size: 17)
        }
    }

    static func name(_ style: LiveryStyle) -> String {
        switch style {
        case .cheatline: "Cheat line"
        case .belly: "Belly"
        case .tailOnly: "Tail only"
        case .topStripe: "Top stripe"
        case .fullBody: "Full body"
        case .splitBody: "Split"
        }
    }
}

/// How the airline looks on a few aircraft, so every change shows at once.
struct LiveryPreview: View {
    let branding: Branding
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LogoView(branding: branding, pixel: 4)
                Text(name.isEmpty ? "YOUR AIRLINE" : name.uppercased()).pixelFont(13.333).foregroundStyle(Theme.textPrimary).lineLimit(2)
            }
            AircraftSpriteView(family: .utilitySingle, branding: branding, pixel: 2)
            AircraftSpriteView(family: .narrowbody, branding: branding, pixel: 2)
            AircraftSpriteView(family: .widebody, branding: branding, pixel: 2)
        }
    }
}

/// The whole look editor: preview on the left, logo and colours on the right.
struct BrandingEditor: View {
    @Binding var branding: Branding
    let airlineName: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ScrollView { Card { LiveryPreview(branding: branding, name: airlineName) } }
                .frame(width: 270)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Logo")
                    LogoEditor(branding: $branding)
                    SectionTitle("Colours")
                    ColourEditor(branding: $branding)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
