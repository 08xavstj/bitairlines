import SwiftUI
import UIKit
import Observation

/// The stand-in used while the ad network is not built in: a full-screen pixel "ad" that counts down, so every reward can be
/// tried now. Closing it early gives nothing, as a real rewarded ad would. Debug builds only: in a Release build
/// `AdConfig.placeholderWithoutSDK` is false, so `isReady` stays false and no ad button shows.
@MainActor
@Observable
final class DevAdService: AdService {
    private(set) var isReady = AdConfig.placeholderWithoutSDK
    var skipsAds: Bool { false }

    func load() { isReady = AdConfig.placeholderWithoutSDK }

    func showRewarded(from: UIViewController?, completion: @escaping (Bool) -> Void) {
        guard isReady, let host = from ?? Ads.topController() else {
            completion(false)
            return
        }
        isReady = false
        let view = AdPlaceholderView(seconds: AdConfig.placeholderSeconds) { [weak self] earned in
            host.dismiss(animated: true) {
                self?.load()
                completion(earned)
            }
        }
        Ads.present(view, over: host, dimmed: false)
    }
}

/// "Ad placeholder, 5 seconds": a countdown, then the reward can be collected. The close button works at any time.
struct AdPlaceholderView: View {
    let finish: (Bool) -> Void
    @State private var left: Int

    init(seconds: Int, finish: @escaping (Bool) -> Void) {
        self.finish = finish
        _left = State(initialValue: seconds)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PixelBackdrop()
            VStack(spacing: 14) {
                PixelIconView(icon: .tv, pixel: 6).foregroundStyle(Theme.accent)
                Text("AD PLACEHOLDER").pixelFont(21.333).foregroundStyle(Theme.accent)
                Text(left > 0 ? "\(left) second\(left == 1 ? "" : "s")" : "Done. The reward is yours.")
                    .pixelFont(13.333).foregroundStyle(Theme.textPrimary)
                Text("A real ad plays here once AdMob is switched on.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                if left == 0 {
                    Button("Collect") { finish(true) }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 260)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { finish(left == 0) } label: { PixelIconView(icon: .close, pixel: 2).foregroundStyle(Theme.textMuted).padding(12) }
                .buttonStyle(.tap)
                .accessibilityLabel(left == 0 ? "Close and collect" : "Close without the reward")
                .padding(8)
        }
        .task {
            while left > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                left -= 1
            }
        }
    }
}
