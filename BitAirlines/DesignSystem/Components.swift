import SwiftUI

/// A label with a value, right-aligned: the basic row of every detail card.
struct KeyValueRow: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.textPrimary
    init(_ label: String, _ value: String, color: Color = Theme.textPrimary) {
        self.label = label
        self.value = value
        self.valueColor = color
    }
    var body: some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(Theme.textMuted)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(valueColor).multilineTextAlignment(.trailing)
        }
        .pixelFont(10.667)
        .accessibilityElement(children: .combine)
    }
}

/// A short empty-state message.
struct EmptyNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).pixelFont(10.667).foregroundStyle(Theme.textMuted).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
    }
}

/// A toggle-style choice chip.
struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).pixelFont(10.667).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
                .background(selected ? Theme.accent : Theme.surfaceRaised, in: PixelShape(step: 2))
        }
        .buttonStyle(.tap)
        .accessibilitySelected(selected)
    }
}

/// How many pages (the list screens) are on screen now. While one is, the game session tells the views about the clock a few
/// times a second instead of on every tick (GameSession.publishIfDue): a long list costs far more to draw again than the map.
@MainActor
enum PageWatch {
    static var shown = 0
}

/// A scrollable page with the game's background and a readable width in landscape.
/// `lazy` builds only the rows that are on screen: use it when the page lists many rows directly (a ForEach right inside the page).
struct Page<Content: View>: View {
    var spacing: CGFloat = 10
    var lazy = false
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            Group {
                if lazy {
                    LazyVStack(alignment: .leading, spacing: spacing) { content }
                } else {
                    VStack(alignment: .leading, spacing: spacing) { content }
                }
            }
            .frame(maxWidth: 900, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity)
        }
        .screenBackground()
        .onAppear { PageWatch.shown += 1 }
        .onDisappear { PageWatch.shown = max(0, PageWatch.shown - 1) }
    }
}

/// A meter with its label and number above it, for a narrow column (the fleet list). StatBar needs about 260 points across.
struct CompactMeter: View {
    let label: String
    let value: Double
    var maximum: Double = 100
    var color: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label.uppercased()).pixelFont(10.667).foregroundStyle(Theme.textMuted).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text("\(Int(value.rounded()))").pixelFont(13.333).foregroundStyle(Theme.textPrimary).lineLimit(1).fixedSize()
            }
            SegmentedMeter(fraction: value / maximum, color: color, segments: 10).frame(height: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(Int(value.rounded())) out of \(Int(maximum))")
    }
}

/// A screen title with an optional trailing control, used at the top of every game screen.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack {
            Text(title.uppercased()).pixelFont(16).foregroundStyle(Theme.accent)
            Spacer()
            trailing
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}
