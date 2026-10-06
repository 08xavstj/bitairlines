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
        VStack(spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 3) {
                    ForEach(row, id: \.self) { index in
                        Swatch(index: index, selected: index == selection, size: size) { selection = index }
                    }
                }
            }
        }
    }

    private func rowIndexes() -> [[Int]] {
        let first = includeNone ? 0 : 1
        let all = Array(first..<PixelPalette.count)
        return stride(from: 0, to: all.count, by: columns).map { Array(all[$0..<min($0 + columns, all.count)]) }
    }
}

/// One colour square. Index 0 is "clear" and shows a cross.
struct Swatch: View {
    let index: Int
    let selected: Bool
    var size: CGFloat = 24
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .accessibilityLabel(index == 0 ? "Clear" : "Colour \(index)")
        .accessibilitySelected(selected)
    }
}
