import PortholeUI
import SwiftUI

struct PortholeAttachmentIdentity: Hashable {
    let enabled: Bool
    let scope: ObjectIdentifier?
}

/// Presents the reusable workspace from the application's injected controller.
struct WherePortholePresentation: ViewModifier {
    let controller: WherePortholeController
    func body(content: Content) -> some View {
        content.portholePresentationAnchor(controller: controller.presentation)
    }
}
