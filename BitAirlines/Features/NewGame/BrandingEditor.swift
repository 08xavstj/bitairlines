import SwiftUI
import CoreCatalog
import CoreWorld

/// How the airline looks on a few aircraft, so every change shows at once.
struct LiveryPreview: View {
    let branding: Branding
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LogoView(branding: branding, pixel: 3)
                Text(name.isEmpty ? "YOUR AIRLINE" : name.uppercased()).pixelFont(13.333).foregroundStyle(Theme.textPrimary).lineLimit(2)
            }
            AircraftSpriteView(family: .utilitySingle, branding: branding, pixel: 2)
            AircraftSpriteView(family: .narrowbody, branding: branding, pixel: 2)
            AircraftSpriteView(family: .widebody, branding: branding, pixel: 2)
        }
    }
}

/// The whole look editor: the preview on the left, and on the right either the colours or the logo.
struct BrandingEditor: View {
    @Binding var branding: Branding
    let airlineName: String
    @State private var page = 0

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ScrollView { Card { LiveryPreview(branding: branding, name: airlineName) } }
                .frame(width: 270)
            VStack(alignment: .leading, spacing: 10) {
                PixelChoice(options: [(label: "Colours", value: 0), (label: "Logo", value: 1)], selection: $page)
                ScrollView {
                    Group {
                        if page == 0 { ColourEditor(branding: $branding) } else { LogoPanel(branding: $branding) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
