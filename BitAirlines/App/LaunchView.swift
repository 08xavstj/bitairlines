import SwiftUI

/// What the game shows when it starts: the studio splash, then the menus.
struct LaunchView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showSplash = LaunchView.splashWanted

    private static var splashWanted: Bool {
        #if DEBUG
        return !Demo.skipSplash
        #else
        return true
        #endif
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if showSplash {
                SplashView { Motion.animate(.easeOut(duration: 0.25)) { showSplash = false } }
            } else {
                RootView()
            }
        }
        .environment(\.pixelStep, max(PixelFont.step(for: dynamicTypeSize), settings.textSize.rawValue))
    }
}
