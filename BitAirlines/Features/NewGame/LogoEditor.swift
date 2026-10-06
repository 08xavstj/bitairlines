import SwiftUI
import CoreCatalog
import CoreWorld

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

/// The logo inside the branding editor: the logo as it is, a button to draw it full screen, and the starter emblems.
struct LogoPanel: View {
    @Binding var branding: Branding
    @State private var drawing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                LogoView(branding: branding, pixel: 4)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your logo goes on the tail of every aircraft.").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    Button("Draw logo") { drawing = true }.buttonStyle(.smallProminent)
                }
            }
            Text("Start from").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            TemplatePicker(branding: $branding, columns: 6, pixel: 2) {}
        }
        .fullScreenCover(isPresented: $drawing) { LogoStudio(branding: $branding) }
    }
}

/// The starter emblems as small pictures, drawn in the airline's own colours.
struct TemplatePicker: View {
    @Binding var branding: Branding
    var columns = 4
    var pixel: CGFloat = 2
    /// Called before a template replaces the logo (so the studio can remember it for Undo).
    let willChange: () -> Void

    var body: some View {
        let all = LogoTemplates.all
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(stride(from: 0, to: all.count, by: columns)), id: \.self) { start in
                HStack(spacing: 6) {
                    ForEach(all[start..<min(start + columns, all.count)]) { template in
                        Button {
                            willChange()
                            branding.logo = template.logo(for: branding)
                        } label: {
                            LogoView(branding: preview(template), pixel: pixel, background: Theme.background)
                                .overlay(Rectangle().stroke(Theme.panelBorder, lineWidth: 1))
                        }
                        .buttonStyle(.tap)
                        .accessibilityLabel(template.name)
                    }
                }
            }
        }
    }

    private func preview(_ template: LogoTemplate) -> Branding {
        var b = branding
        b.logo = template.logo(for: branding)
        return b
    }
}

/// Full-screen logo drawing: a big canvas on the left, tools, colours and emblems on the right.
struct LogoStudio: View {
    @Binding var branding: Branding
    @Environment(\.dismiss) private var dismiss
    @State private var tool: LogoTool = .pen
    @State private var colour = PixelPalette.orange
    @State private var mirror = true
    @State private var undoStack: [[UInt8]] = []

    var body: some View {
        GeometryReader { geo in
            let cell = max(8, floor((geo.size.height - 8) / CGFloat(Branding.logoSize)))
            HStack(alignment: .top, spacing: 16) {
                LogoCanvas(branding: $branding, tool: tool, colour: colour, mirror: mirror, cell: cell) { remember() }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("LOGO").pixelFont(16).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Button("Done") { dismiss() }.buttonStyle(.smallProminent)
                        }
                        HStack(spacing: 6) {
                            ForEach(LogoTool.allCases) { t in Chip(title: t.label, selected: tool == t) { tool = t } }
                            Chip(title: "Mirror", selected: mirror) { mirror.toggle() }
                        }
                        HStack(spacing: 6) {
                            Button("Undo") { undo() }.buttonStyle(.small).disabled(undoStack.isEmpty)
                            Button("Clear") { remember(); branding.logo = Branding.blankLogo() }.buttonStyle(.small)
                        }
                        Text("Your colours").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                        HStack(spacing: 6) {
                            ForEach(Array([branding.primary, branding.secondary, branding.accent, PixelPalette.white, PixelPalette.ink].enumerated()), id: \.offset) { _, index in
                                Swatch(index: index, selected: colour == index, size: 32) { colour = index; if tool == .erase { tool = .pen } }
                            }
                        }
                        Text("All colours").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                        PaletteGrid(selection: Binding(get: { colour }, set: { colour = $0; if tool == .erase { tool = .pen } }), columns: 8, size: 24)
                        Text("Start from").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                        TemplatePicker(branding: $branding, columns: 4, pixel: 2) { remember() }
                    }
                }
            }
            .padding(4)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .screenBackground()
    }

    private func remember() {
        undoStack.append(branding.logo)
        if undoStack.count > 40 { undoStack.removeFirst() }
    }

    private func undo() {
        guard let last = undoStack.popLast() else { return }
        branding.logo = last
    }
}

/// The drawing grid. One touch is one step for Undo; a fill acts once per touch.
struct LogoCanvas: View {
    @Binding var branding: Branding
    let tool: LogoTool
    let colour: Int
    let mirror: Bool
    let cell: CGFloat
    let willChange: () -> Void
    @State private var strokeStarted = false

    var body: some View {
        let n = Branding.logoSize
        let side = cell * CGFloat(n)
        Canvas { context, _ in
            for y in 0..<n {
                for x in 0..<n {
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
                guard x >= 0, y >= 0, x < n, y < n else { return }
                let first = !strokeStarted
                if first { willChange(); strokeStarted = true }
                switch tool {
                case .pen: paint(x: x, y: y, colour: colour)
                case .erase: paint(x: x, y: y, colour: 0)
                case .fill: if first { flood(x: x, y: y) }
                }
            }
            .onEnded { _ in strokeStarted = false })
        .accessibilityLabel("Logo canvas")
    }

    private func paint(x: Int, y: Int, colour: Int) {
        branding.setLogoPixel(x: x, y: y, colour: colour)
        if mirror { branding.setLogoPixel(x: Branding.logoSize - 1 - x, y: y, colour: colour) }
    }

    private func flood(x: Int, y: Int) {
        let n = Branding.logoSize
        let target = branding.logoPixel(x: x, y: y)
        guard target != colour else { return }
        var logo = branding
        var queue = [(x, y)]
        var seen = Set<Int>()
        while let (cx, cy) = queue.popLast() {
            guard cx >= 0, cy >= 0, cx < n, cy < n else { continue }
            let key = cy * n + cx
            guard !seen.contains(key), logo.logoPixel(x: cx, y: cy) == target else { continue }
            seen.insert(key)
            logo.setLogoPixel(x: cx, y: cy, colour: colour)
            queue.append((cx + 1, cy)); queue.append((cx - 1, cy)); queue.append((cx, cy + 1)); queue.append((cx, cy - 1))
        }
        branding = logo
    }
}
