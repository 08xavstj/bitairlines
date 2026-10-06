import SwiftUI

@main
struct BitAirlinesApp: App {
    @State private var settings = AppSettings()

    init() { PixelFont.register() }

    var body: some Scene {
        WindowGroup {
            LaunchView()
                .environment(settings)
                .preferredColorScheme(.dark)
        }
    }
}
