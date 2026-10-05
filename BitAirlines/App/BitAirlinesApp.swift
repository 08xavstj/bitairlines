import SwiftUI

@main
struct BitAirlinesApp: App {
    init() { PixelFont.register() }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}
