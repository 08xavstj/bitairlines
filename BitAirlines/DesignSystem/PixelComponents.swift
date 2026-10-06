import SwiftUI

/// A panel for grouping content: stepped corners, border and a hard shadow.
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PixelPanel())
    }
}

/// Lets two different button styles sit in one conditional.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { PrimaryButtonChrome(label: configuration.label, pressed: configuration.isPressed) }
}

struct PrimaryButtonChrome<Label: View>: View {
    let label: Label
    var pressed = false
    @Environment(\.isEnabled) var isEnabled
    @Environment(\.pixelStep) var step
    var body: some View {
        label
            .pixelFont(13.333)
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 42 + 8 * CGFloat(step))
            .background(
                ZStack {
                    PixelShape(step: 2).fill(isEnabled ? Theme.accentDark : Color.black.opacity(0.4)).offset(y: pressed ? 1 : 4)
                    PixelShape(step: 2).fill(isEnabled ? Theme.accent : Theme.textMuted.opacity(0.5)).offset(y: pressed ? 3 : 0)
                }
            )
            .padding(.bottom, 4)
            .offset(y: pressed ? 2 : 0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { SecondaryButtonChrome(label: configuration.label, pressed: configuration.isPressed) }
}

struct SecondaryButtonChrome<Label: View>: View {
    let label: Label
    var pressed = false
    @Environment(\.isEnabled) var isEnabled
    @Environment(\.pixelStep) var step
    var body: some View {
        label
            .pixelFont(13.333)
            .foregroundStyle(isEnabled ? Theme.accent : Theme.textMuted)
            .frame(maxWidth: .infinity, minHeight: 42 + 8 * CGFloat(step))
            .background(
                ZStack {
                    PixelShape(step: 2).fill(Theme.shadow).offset(y: pressed ? 1 : 4)
                    PixelShape(step: 2).fill(Theme.surfaceRaised).offset(y: pressed ? 3 : 0)
                    PixelShape(step: 2).inset(by: 1).stroke(isEnabled ? Theme.accent.opacity(0.7) : Theme.panelBorder, lineWidth: 2).offset(y: pressed ? 3 : 0)
                }
            )
            .padding(.bottom, 4)
            .offset(y: pressed ? 2 : 0)
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(Theme.accent).frame(width: 6, height: 6)
            Text(text.uppercased()).pixelFont(13.333).foregroundStyle(Theme.textMuted)
            Rectangle().fill(Theme.separator).frame(height: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A labelled segmented meter with the value spelled out (never relies on colour alone).
struct StatBar: View {
    @Environment(\.pixelStep) var step
    let label: String
    let value: Double
    var maximum: Double = 100
    var color: Color = Theme.accent
    var valueText: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(label).pixelFont(10.667).foregroundStyle(Theme.textMuted).lineLimit(1).minimumScaleFactor(0.7).frame(width: 84 + 26 * CGFloat(step), alignment: .leading)
            SegmentedMeter(fraction: value / maximum, color: color).frame(height: 10)
            Text(valueText ?? "\(Int(value.rounded()))").pixelFont(13.333).foregroundStyle(Theme.textPrimary).lineLimit(1).fixedSize().frame(minWidth: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(valueText ?? "\(Int(value.rounded())) out of \(Int(maximum))")")
    }
}

/// Chunky blocks, filled from the left.
struct SegmentedMeter: View {
    let fraction: Double
    var color: Color = Theme.accent
    var segments = 20
    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 2
            let width = (size.width - gap * CGFloat(segments - 1)) / CGFloat(segments)
            let filled = Int((min(1, max(0, fraction)) * Double(segments)).rounded(fraction > 0 ? .up : .down))
            for i in 0..<segments {
                let rect = CGRect(x: CGFloat(i) * (width + gap), y: 0, width: width, height: size.height)
                context.fill(Path(rect), with: .color(i < filled ? color : Theme.surfaceRaised), style: FillStyle(antialiased: false))
            }
        }
    }
}

/// A small tag with square corners.
struct Tag: View {
    let text: String
    var color: Color = Theme.accent
    var body: some View {
        Text(text.uppercased())
            .pixelFont(10.667)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(PixelShape(step: 1).fill(color.opacity(0.16)))
            .overlay(PixelShape(step: 1).inset(by: 0.5).stroke(color.opacity(0.55), lineWidth: 1))
    }
}

extension View {
    /// The game's wall: dark, with a faint dither.
    func screenBackground() -> some View {
        self.background(PixelBackdrop()).scrollContentBackground(.hidden)
    }
}

// MARK: - Small controls

/// A compact pixel button for rows and cards. `.prominent` is the accent one; `.danger` is red.
struct SmallButtonStyle: ButtonStyle {
    enum Kind { case prominent, plain, danger }
    var kind: Kind = .plain
    func makeBody(configuration: Configuration) -> some View { SmallButtonChrome(label: configuration.label, kind: kind, pressed: configuration.isPressed) }
}

struct SmallButtonChrome<Label: View>: View {
    let label: Label
    var kind: SmallButtonStyle.Kind = .plain
    var pressed = false
    @Environment(\.isEnabled) var isEnabled
    @Environment(\.pixelStep) var step

    var body: some View {
        let tint: Color = kind == .danger ? Theme.bad : Theme.accent
        let fill: Color = kind == .prominent ? (isEnabled ? Theme.accent : Theme.textMuted.opacity(0.45)) : Theme.surfaceRaised
        let text: Color = kind == .prominent ? Theme.onAccent : (isEnabled ? tint : Theme.textMuted)
        label
            .pixelFont(10.667).lineLimit(1).fixedSize()
            .foregroundStyle(text)
            .padding(.horizontal, 12).frame(minHeight: 32 + 6 * CGFloat(step))
            .background(
                ZStack {
                    PixelShape(step: 2).fill(kind == .prominent && isEnabled ? Theme.accentDark : Theme.shadow).offset(y: pressed ? 1 : 3)
                    PixelShape(step: 2).fill(fill).offset(y: pressed ? 2 : 0)
                    if kind != .prominent { PixelShape(step: 2).inset(by: 1).stroke(isEnabled ? tint.opacity(0.7) : Theme.panelBorder, lineWidth: 2).offset(y: pressed ? 2 : 0) }
                }
            )
            .padding(.bottom, 3)
            .offset(y: pressed ? 1 : 0)
    }
}

extension ButtonStyle where Self == SmallButtonStyle {
    static var small: SmallButtonStyle { SmallButtonStyle(kind: .plain) }
    static var smallProminent: SmallButtonStyle { SmallButtonStyle(kind: .prominent) }
    static var smallDanger: SmallButtonStyle { SmallButtonStyle(kind: .danger) }
}

/// A chunky square switch.
struct PixelToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 10) {
                configuration.label
                Spacer(minLength: 8)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    PixelShape(step: 2).fill(configuration.isOn ? Theme.accentDark : Theme.surfaceRaised)
                    PixelShape(step: 2).inset(by: 1).stroke(configuration.isOn ? Theme.accent : Theme.panelBorder, lineWidth: 2)
                    Rectangle().fill(configuration.isOn ? Theme.accent : Theme.textMuted).frame(width: 16, height: 16).padding(4)
                }
                .frame(width: 52, height: 28)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// A row of exclusive choices (like a segmented control, in pixels).
struct PixelChoice<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label.uppercased()).pixelFont(10.667).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(on ? Theme.onAccent : Theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(PixelShape(step: 2).fill(on ? Theme.accent : Theme.surfaceRaised))
                        .overlay(PixelShape(step: 2).inset(by: 1).stroke(on ? Theme.accentDark : Theme.panelBorder, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilitySelected(on)
            }
        }
    }
}

/// A text field in a pixel panel.
struct PixelField: View {
    let title: String
    @Binding var text: String
    var prompt: String
    var capitalization: TextInputAutocapitalization = .words

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).pixelFont(10.667).foregroundStyle(Theme.textMuted)
            TextField("", text: $text, prompt: Text(prompt.uppercased()).foregroundStyle(Theme.textMuted.opacity(0.6)))
                .pixelFont(13.333).foregroundStyle(Theme.textPrimary).tint(Theme.accent)
                .textInputAutocapitalization(capitalization).autocorrectionDisabled()
                .padding(.horizontal, 10).frame(minHeight: 40)
                .background(PixelShape(step: 2).fill(Theme.background))
                .overlay(PixelShape(step: 2).inset(by: 1).stroke(Theme.panelBorder, lineWidth: 2))
                .accessibilityLabel(title)
        }
    }
}

/// A square button with a pixel icon (plus, minus, close...).
struct PixelSquareButton: View {
    let icon: PixelIcon
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) var isEnabled
    var body: some View {
        Button(action: action) {
            PixelIconView(icon: icon, pixel: 2).foregroundStyle(isEnabled ? Theme.accent : Theme.textMuted.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(PixelShape(step: 2).fill(Theme.surfaceRaised))
                .overlay(PixelShape(step: 2).inset(by: 1).stroke(isEnabled ? Theme.accent.opacity(0.6) : Theme.panelBorder, lineWidth: 2))
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }
}

/// A value with minus and plus buttons.
struct PixelStepper: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    /// How the value reads, when it is not just the number.
    var display: (Double) -> String = { "\(Int($0.rounded()))" }
    var body: some View {
        HStack(spacing: 10) {
            Text(label).pixelFont(13.333).foregroundStyle(Theme.textPrimary)
            Spacer()
            PixelSquareButton(icon: .minus, label: "Decrease \(label)") { value = max(range.lowerBound, value - step) }.disabled(value <= range.lowerBound)
            Text(display(value)).pixelFont(13.333).foregroundStyle(Theme.textPrimary).frame(minWidth: 52)
                .accessibilityLabel("\(label): \(display(value))")
            PixelSquareButton(icon: .plus, label: "Increase \(label)") { value = min(range.upperBound, value + step) }.disabled(value >= range.upperBound)
        }
    }
}

// MARK: - Dialogs

/// The game's own alert and confirmation box (pixel panel over a dimmed screen).
struct PixelDialogModifier: ViewModifier {
    let title: String
    let message: String?
    @Binding var isPresented: Bool
    var confirmTitle: String?
    var destructive = false
    var cancelTitle = "OK"
    var onConfirm: () -> Void = {}

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack {
                        Color.black.opacity(0.62).ignoresSafeArea().onTapGesture { if confirmTitle == nil { isPresented = false } }
                        VStack(alignment: .leading, spacing: 12) {
                            Text(title.uppercased()).pixelFont(16).foregroundStyle(destructive ? Theme.bad : Theme.accent).fixedSize(horizontal: false, vertical: true)
                            if let message { Text(message).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true) }
                            HStack(spacing: 10) {
                                Button(confirmTitle == nil ? cancelTitle : "Cancel") { isPresented = false }
                                    .buttonStyle(confirmTitle == nil ? AnyButtonStyle(PrimaryButtonStyle()) : AnyButtonStyle(SecondaryButtonStyle()))
                                if let confirmTitle {
                                    Button(confirmTitle) { onConfirm(); isPresented = false }
                                        .buttonStyle(destructive ? AnyButtonStyle(DangerWideButtonStyle()) : AnyButtonStyle(PrimaryButtonStyle()))
                                }
                            }
                        }
                        .padding(16).frame(maxWidth: 460)
                        .background(PixelPanel(fill: Theme.surface, border: destructive ? Theme.bad.opacity(0.7) : Theme.accent.opacity(0.7)))
                        .padding(24)
                        .accessibilityAddTraits(.isModal)
                    }
                    .transition(.opacity)
                }
            }
            .animation(Motion.animation(.easeOut(duration: 0.15)), value: isPresented)
    }
}

/// A full-width red button for destructive confirmations.
struct DangerWideButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { DangerWideChrome(label: configuration.label, pressed: configuration.isPressed) }
}

struct DangerWideChrome<Label: View>: View {
    let label: Label
    var pressed = false
    @Environment(\.pixelStep) var step
    var body: some View {
        label
            .pixelFont(13.333).foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 42 + 8 * CGFloat(step))
            .background(ZStack {
                PixelShape(step: 2).fill(Color(hex: 0x8C2F2A)).offset(y: pressed ? 1 : 4)
                PixelShape(step: 2).fill(Theme.bad).offset(y: pressed ? 3 : 0)
            })
            .padding(.bottom, 4).offset(y: pressed ? 2 : 0)
    }
}

extension View {
    /// A message with one OK button.
    func pixelAlert(_ title: String, message: String?, isPresented: Binding<Bool>) -> some View {
        modifier(PixelDialogModifier(title: title, message: message, isPresented: isPresented))
    }

    /// A question with Cancel and a confirm button.
    func pixelConfirm(_ title: String, message: String? = nil, confirm: String, destructive: Bool = false, isPresented: Binding<Bool>, action: @escaping () -> Void) -> some View {
        modifier(PixelDialogModifier(title: title, message: message, isPresented: isPresented, confirmTitle: confirm, destructive: destructive, onConfirm: action))
    }
}
