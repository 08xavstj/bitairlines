import SwiftUI
import UIKit
import CoreCatalog
import CoreWorld

/// A pixel postcard of the airline: its biggest aircraft in the livery over the home strip, the logo, the name and the home airport.
struct Postcard: View {
    let branding: Branding
    let airlineName: String
    let homeName: String
    let family: SpriteFamily

    static let size = CGSize(width: 360, height: 200)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in PostcardSky.paint(&context, size: size) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    LogoView(branding: branding, pixel: 2, background: Livery.color(PixelPalette.white))
                        .overlay(Rectangle().stroke(Livery.color(PixelPalette.ink), lineWidth: 2))
                    VStack(alignment: .leading, spacing: 2) {
                        // Names are up to 22 letters: two lines at most, never cut off.
                        Text(airlineName.uppercased()).pixelFont(16).foregroundStyle(Livery.color(PixelPalette.ink)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text("Home: \(homeName)").pixelFont(10.667).foregroundStyle(Livery.color(PostcardSky.navy)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            AircraftSpriteView(family: family, branding: branding, pixel: 3)
                .position(x: Postcard.size.width * 0.55, y: Postcard.size.height - 58)
            Text("PIXEL PROPS").pixelFont(8).foregroundStyle(Livery.color(PixelPalette.white))
                .position(x: Postcard.size.width - 40, y: Postcard.size.height - 9)
        }
        .frame(width: Postcard.size.width, height: Postcard.size.height)
        .clipped()
    }

    /// The postcard for a world: the aircraft with the most seats in the fleet (or a bush plane before there is one).
    init(world: World) {
        branding = world.airline.branding
        airlineName = world.airline.name
        homeName = AirportCatalog.airport(world.airline.home)?.label ?? world.airline.home
        family = world.aircraft.compactMap(\.type).max { $0.seats < $1.seats }?.family ?? .utilitySingle
    }
}

/// The postcard's sky and ground, in flat palette colours and whole blocks.
enum PostcardSky {
    static let navy = 19
    static let ice = 22
    static let forest = 13
    static let slate = 3

    static func paint(_ context: inout GraphicsContext, size: CGSize) {
        func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ colour: Int) {
            context.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(Livery.color(colour)), style: FillStyle(antialiased: false))
        }
        block(0, 0, size.width, size.height, PixelPalette.sky)
        // Clouds: stacked blocks.
        for (x, y) in [(200.0, 26.0), (290.0, 58.0), (60.0, 92.0)] {
            block(x, y, 56, 8, ice)
            block(x + 10, y - 8, 30, 8, ice)
            block(x + 4, y + 8, 44, 4, PixelPalette.white)
        }
        // Ground, the strip and its markings.
        let ground = size.height - 34
        block(0, ground, size.width, 34, forest)
        block(0, ground + 10, size.width, 12, slate)
        var x: CGFloat = 8
        while x < size.width {
            block(x, ground + 15, 12, 2, PixelPalette.white)
            x += 28
        }
    }
}

/// Makes the postcard picture and the livery code, and shares them.
struct ShareAirlineSheet: View {
    let world: World
    @Environment(\.dismiss) private var dismiss
    @State private var picture: UIImage?
    @State private var copied = false

    var body: some View {
        let code = LiveryCode.encode(world.airline.branding)
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(title: "Share your airline") { Button("Close") { dismiss() }.buttonStyle(.small) }
            ScrollView {
                HStack(alignment: .top, spacing: 14) {
                    Postcard(world: world)
                        .overlay(Rectangle().stroke(Theme.panelBorder, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LIVERY CODE").pixelFont(13.333).foregroundStyle(Theme.accent)
                        Text("Anyone can paste this under Import code in the colour editor to paint their airline the same way.")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        Text(code).pixelFont(10.667).foregroundStyle(Theme.textPrimary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Button(copied ? "Copied" : "Copy code") {
                            UIPasteboard.general.string = code
                            copied = true
                        }
                        .buttonStyle(.small)
                        if let picture {
                            let image = Image(uiImage: picture)
                            ShareLink(item: image, subject: Text(world.airline.name), message: Text("My airline in Pixel Props. Livery code: \(code)"),
                                      preview: SharePreview(world.airline.name, image: image)) {
                                Text("Share postcard")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .screenBackground()
        .onAppear { picture = ShareAirlineSheet.render(world) }
    }

    /// The postcard as a picture, three screen pixels to each point so the pixel art stays sharp.
    @MainActor
    static func render(_ world: World) -> UIImage? {
        let renderer = ImageRenderer(content: Postcard(world: world))
        renderer.scale = 3
        return renderer.uiImage
    }
}
