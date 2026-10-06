import SwiftUI
import CoreCatalog
import CoreWorld

/// The three airline colours. Tap a colour slot, then tap a colour below to change it.
struct ColourEditor: View {
    @Binding var branding: Branding
    @State private var role: ColourRole = .main

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(ColourRole.allCases) { r in RoleButton(role: r, colour: branding[keyPath: r.keyPath], selected: role == r) { role = r } }
            }
            PaletteGrid(selection: Binding(get: { branding[keyPath: role.keyPath] }, set: { branding[keyPath: role.keyPath] = $0 }), columns: 11, size: 24)
            Text("Colour sets").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            ColourSets(branding: $branding)
            Text("Paint scheme").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            FlowRow(items: LiveryStyle.allCases) { style in
                Chip(title: ColourEditor.name(style), selected: branding.style == style) { branding.style = style }
            }
            Text("Livery code").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            LiveryCodeImport(branding: $branding)
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

/// Which of the three airline colours the palette is changing.
enum ColourRole: String, CaseIterable, Identifiable {
    case main, stripe, detail
    var id: String { rawValue }
    var label: String {
        switch self {
        case .main: "Main"
        case .stripe: "Stripe"
        case .detail: "Detail"
        }
    }
    var keyPath: WritableKeyPath<Branding, Int> {
        switch self {
        case .main: \.primary
        case .stripe: \.secondary
        case .detail: \.accent
        }
    }
}

/// A colour slot: its colour and its name, outlined when the palette is changing it.
struct RoleButton: View {
    let role: ColourRole
    let colour: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Rectangle().fill(Livery.color(colour)).frame(width: 20, height: 20).overlay(Rectangle().stroke(Theme.panelBorder, lineWidth: 1))
                Text(role.label.uppercased()).pixelFont(10.667).foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
            }
            .padding(.horizontal, 8).frame(minHeight: 34)
            .background(PixelShape(step: 2).fill(selected ? Theme.accent : Theme.surfaceRaised))
        }
        .buttonStyle(.tap)
        .accessibilitySelected(selected)
    }
}

/// Ready-made colour combinations that work together, one tap each.
struct ColourSets: View {
    @Binding var branding: Branding

    /// Main, stripe, detail as palette indexes.
    /// White and sky, white and navy, navy and white, white and forest, red, teal, white and maroon, black and amber.
    static let sets: [(Int, Int, Int)] = [
        (6, 21, 10), (6, 19, 8), (19, 6, 11), (6, 13, 11), (8, 6, 1), (16, 6, 10), (6, 7, 30), (31, 11, 6),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(ColourSets.sets.enumerated()), id: \.offset) { _, set in
                Button {
                    branding.primary = set.0
                    branding.secondary = set.1
                    branding.accent = set.2
                } label: {
                    VStack(spacing: 0) {
                        Rectangle().fill(Livery.color(set.0)).frame(height: 14)
                        Rectangle().fill(Livery.color(set.1)).frame(height: 6)
                        Rectangle().fill(Livery.color(set.2)).frame(height: 6)
                    }
                    .frame(width: 30)
                    .overlay(Rectangle().stroke(Theme.panelBorder, lineWidth: 1))
                }
                .buttonStyle(.tap)
                .accessibilityLabel("Colour set")
            }
        }
    }
}

/// Wraps items onto as many rows as they need, three to a row.
struct FlowRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    var perRow = 3
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(stride(from: 0, to: items.count, by: perRow)), id: \.self) { start in
                HStack(spacing: 6) {
                    ForEach(items[start..<min(start + perRow, items.count)], id: \.self) { content($0) }
                }
            }
        }
    }
}
