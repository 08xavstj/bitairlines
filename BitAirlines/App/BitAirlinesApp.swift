import SwiftUI

@main
struct BitAirlinesApp: App {
    @State private var settings: AppSettings
    @State private var audio: AudioEngine

    init() {
        PixelFont.register()
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _audio = State(initialValue: AudioEngine(output: AudioEngine.makeOutput(), settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            LaunchView()
                .environment(settings)
                .environment(\.audio, audio)
                .preferredColorScheme(.dark)
        }
    }
}
