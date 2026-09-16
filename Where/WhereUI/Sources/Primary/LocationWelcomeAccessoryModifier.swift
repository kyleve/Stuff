import SwiftUI

/// Adds the system tab accessory only while live-region status is visible.
struct LocationWelcomeAccessoryModifier: ViewModifier {
    let accessory: LocationWelcomeModel.Accessory?

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: accessory != nil) {
                if let accessory {
                    LocationWelcomeStatusAccessory(accessory: accessory)
                }
            }
        } else {
            content
        }
    }
}
