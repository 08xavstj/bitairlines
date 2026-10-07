import SwiftUI
import CoreCatalog
import CoreWorld

/// What the hangar shows: a search by maker or model, a certificate level, and whether it must fit an airport you use.
struct MarketFilter: Equatable {
    var query = ""
    /// 0 shows every level.
    var level = 0
    var fitsOnly = false

    func matches(_ type: AircraftType, fit: AircraftFit) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty && !type.displayName.lowercased().contains(q) && !type.id.contains(q) { return false }
        if level != 0 && type.level != level { return false }
        // Fits my airports: some airport of the network takes it as delivered. That is exactly when it can be bought (an aircraft
        // is delivered to home, or to the nearest airport of the network it can use: World.deliveryAirport).
        if fitsOnly && !fit.fitsAny { return false }
        return true
    }
}

/// The search field, the fit switch and the level, on one compact row above the list.
struct MarketFilterBar: View {
    @Binding var filter: MarketFilter

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $filter.query, prompt: Text("SEARCH").foregroundStyle(Theme.textMuted.opacity(0.6)))
                .pixelFont(13.333).foregroundStyle(Theme.textPrimary).tint(Theme.accent)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.horizontal, 10).frame(minHeight: 44)
                .background(PixelShape(step: 2).fill(Theme.background))
                .overlay(PixelShape(step: 2).inset(by: 1).stroke(Theme.panelBorder, lineWidth: 2))
                .accessibilityLabel("Search by maker or model")
            HangarSwitch(title: "Fits my airports", isOn: $filter.fitsOnly)
            HangarLevelPicker(level: $filter.level)
        }
    }
}

/// A button that is lit while its filter is on.
struct HangarSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 6) {
                Rectangle().fill(isOn ? Theme.onAccent : Color.clear).frame(width: 10, height: 10)
                    .overlay(Rectangle().stroke(isOn ? Theme.onAccent : Theme.textMuted, lineWidth: 2))
                Text(title.uppercased()).pixelFont(10.667).lineLimit(1).fixedSize()
            }
            .foregroundStyle(isOn ? Theme.onAccent : Theme.textPrimary)
            .padding(.horizontal, 10).frame(minHeight: 44)
            .background(PixelShape(step: 2).fill(isOn ? Theme.accent : Theme.surfaceRaised))
            .overlay(PixelShape(step: 2).inset(by: 1).stroke(isOn ? Theme.accentDark : Theme.panelBorder, lineWidth: 2))
        }
        .buttonStyle(.tap)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// Minus, the level, plus. 0 means any level.
struct HangarLevelPicker: View {
    @Binding var level: Int
    static let top = 7

    var body: some View {
        HStack(spacing: 4) {
            stepButton(.minus, label: "Lower level", enabled: level > 0) { level -= 1 }
            Text(level == 0 ? "ANY LEVEL" : "LEVEL \(level)").pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).fixedSize().frame(minWidth: 80)
                .accessibilityLabel(level == 0 ? "Any level" : "Level \(level)")
            stepButton(.plus, label: "Higher level", enabled: level < HangarLevelPicker.top) { level += 1 }
        }
    }

    private func stepButton(_ icon: PixelIcon, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PixelIconView(icon: icon, pixel: 2).foregroundStyle(enabled ? Theme.accent : Theme.textMuted.opacity(0.5))
                .frame(width: 44, height: 44)
                .background(PixelShape(step: 2).fill(Theme.surfaceRaised))
                .overlay(PixelShape(step: 2).inset(by: 1).stroke(enabled ? Theme.accent.opacity(0.6) : Theme.panelBorder, lineWidth: 2))
        }
        .buttonStyle(.tap)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
