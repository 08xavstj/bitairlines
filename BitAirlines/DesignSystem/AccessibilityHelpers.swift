import SwiftUI

extension View {
    /// Marks a view as the selected one of a group for VoiceOver.
    @ViewBuilder func accessibilitySelected(_ selected: Bool) -> some View {
        if selected { accessibilityAddTraits(.isSelected) } else { self }
    }
}
