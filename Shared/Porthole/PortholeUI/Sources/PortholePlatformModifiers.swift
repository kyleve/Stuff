import SwiftUI

extension View {
    @ViewBuilder func portholeInlineNavigationTitle() -> some View {
        #if canImport(UIKit)
            navigationBarTitleDisplayMode(.inline)
        #else
            self
        #endif
    }

    @ViewBuilder func portholeCodeInput() -> some View {
        #if canImport(UIKit)
            autocorrectionDisabled().textInputAutocapitalization(.never)
        #else
            autocorrectionDisabled()
        #endif
    }
}
