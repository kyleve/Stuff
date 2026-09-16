import SwiftUI

/// Keeps the tab navigation tree stable on iOS 26.0, which cannot dynamically
/// enable or disable a native tab-view bottom accessory.
struct LegacyLocationWelcomeAccessoryModifier: ViewModifier {
    let accessory: LocationWelcomeModel.Accessory?

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if let accessory {
                    LocationWelcomeStatusAccessory(accessory: accessory)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.horizontal)
                }
            }
        }
    }
}
