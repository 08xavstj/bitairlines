import SwiftUI
import CoreWorld

struct RootView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("BIT AIRLINES").font(Theme.title(32)).foregroundStyle(Theme.accent)
                Text("Rules v\(WorldInfo.rulesVersion)").font(Theme.body).foregroundStyle(Theme.textMuted)
            }
        }
    }
}
