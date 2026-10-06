import SwiftUI

/// The Privacy card in Settings: the privacy policy, and with AdMob built in a line on tracking and Google's form to change or
/// withdraw ad consent (shown only where Google says it is needed: EU, UK, Switzerland).
struct PrivacyCard: View {
    @State private var adChoices = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("PRIVACY").pixelFont(13.333).foregroundStyle(Theme.accent)
                if let note = AdConsent.privacyNote {
                    Text(note).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    PrivacyPolicyButton()
                    if adChoices {
                        Button("Ad privacy choices") {
                            AdConsent.showPrivacyChoices { adChoices = AdConsent.privacyChoicesRequired }
                        }
                        .buttonStyle(.small)
                    }
                }
            }
        }
        .onAppear {
            adChoices = AdConsent.privacyChoicesRequired
            // The answer is known only after Google's status has been fetched once this launch.
            AdConsent.refresh { _ in adChoices = AdConsent.privacyChoicesRequired }
        }
    }
}

/// Opens the privacy policy (AppLinks.privacyPolicy) in the web browser.
struct PrivacyPolicyButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Privacy policy") { openURL(AppLinks.privacyPolicy) }
            .buttonStyle(.small)
            .accessibilityHint("Opens the privacy policy in your web browser.")
    }
}
