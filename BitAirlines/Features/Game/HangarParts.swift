import SwiftUI

/// Small shared pieces for the hangar, fleet, bases and pilots screens.

/// A button caption that keeps the tap area near 44 points (the small button style alone is about 35).
struct HangarButtonText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).frame(minWidth: 52, minHeight: 40)
    }
}

/// A refusal shown at the top of a sheet, so it is seen even when the button that caused it is far down the page.
/// Tap it to clear it.
struct HangarNotice: View {
    let session: GameSession

    var body: some View {
        if let notice = session.notice {
            Button { session.notice = nil } label: {
                Text(notice).pixelFont(10.667).foregroundStyle(Theme.gold)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(PixelPanel())
            }
            .buttonStyle(.tap)
            .accessibilityLabel(notice)
            .accessibilityHint("Tap to hide.")
        }
    }
}

/// The price and the buy button on the right of a card for sale. Says why it cannot be bought, when it cannot.
struct HangarPriceColumn: View {
    let priceText: String
    let price: Int
    let cash: Int
    /// The level needed, when the airline has not reached it yet.
    let neededLevel: Int?
    /// True when no airport of the airline's network can take it, so it cannot be delivered (World.deliveryProblem; the card
    /// says why). The core would refuse the purchase, so no button is offered.
    var cannotDeliver = false
    let action: String
    let onBuy: () -> Void

    var body: some View {
        let affordable = cash >= price
        VStack(alignment: .trailing, spacing: 6) {
            Text(priceText).pixelFont(13.333).foregroundStyle(affordable ? Theme.good : Theme.bad)
            if let neededLevel {
                Tag(text: "Needs level \(neededLevel)", color: Theme.bad)
            } else if cannotDeliver {
                Tag(text: "Cannot deliver", color: Theme.bad)
            } else {
                Button { onBuy() } label: { HangarButtonText(action) }
                    .buttonStyle(.smallProminent)
                    .disabled(!affordable)
                if !affordable {
                    Text("Need \(Format.compactMoney(price - cash)) more").pixelFont(10.667).foregroundStyle(Theme.bad)
                }
            }
        }
        .fixedSize()
    }
}
