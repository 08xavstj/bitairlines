import SwiftUI
import UIKit
import CoreWorld

/// Paste a livery code another player shared to copy their look (colours, paint scheme and logo), or copy your own.
/// The code itself is made and read in AirlineCore (LiveryCode.swift).
struct LiveryCodeImport: View {
    @Binding var branding: Branding
    @State private var text = ""
    @State private var message: String?
    @State private var good = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PixelField(title: "Import code", text: $text, prompt: "PROPS-...", capitalization: .characters)
            HStack(spacing: 8) {
                Button("Use this look") { use() }.buttonStyle(.smallProminent).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Copy my code") {
                    UIPasteboard.general.string = LiveryCode.encode(branding)
                    good = true
                    message = "Your code is copied. Paste it anywhere to share your look."
                }
                .buttonStyle(.small)
            }
            if let message {
                Text(message).pixelFont(10.667).foregroundStyle(good ? Theme.good : Theme.bad).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func use() {
        do {
            branding = try LiveryCode.decode(text)
            good = true
            message = "Done. The colours, paint scheme and logo now match the code."
            text = ""
        } catch let error as LiveryCodeError {
            good = false
            message = LiveryCodeImport.describe(error)
        } catch {
            good = false
            message = "That code did not work."
        }
    }

    static func describe(_ error: LiveryCodeError) -> String {
        switch error {
        case .wrongPrefix: "A livery code starts with PROPS-."
        case .badCharacter: "The code has a letter that does not belong in it. Check for a typo."
        case .tooShort, .badChecksum: "Part of the code is missing or mistyped. Copy it again in one piece."
        case .unknownVersion: "This code comes from a newer version of the game."
        case .badColour, .badScheme, .badLogo: "This code is damaged. Ask for it again."
        }
    }
}
