import SwiftUI

/// "+$1.2K" beside the bank total when a flight or job pays. It shows for a moment, then fades.
struct PayoutTag: View {
    let payout: Payout?
    @State private var visible = false

    var body: some View {
        Text(payout.map { Format.signedMoney($0.amount) } ?? "")
            .pixelFont(10.667)
            .foregroundStyle(Theme.good)
            .opacity(visible ? 1 : 0)
            .offset(y: visible || Motion.reduced ? 0 : -4)
            .accessibilityHidden(true)
            .task(id: payout) {
                guard payout != nil else { return }
                visible = true
                try? await Task.sleep(nanoseconds: UInt64(Payout.showSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                Motion.animate(.easeOut(duration: 0.4)) { visible = false }
            }
    }
}
