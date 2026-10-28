import SwiftUI

/// Keeps the welcome card's authored dismiss control in the same finish as its card.
struct RegionWelcomeCloseSurface: ViewModifier {
    let style: WhereStylesheet.LocationWelcomeStyle.Close
    let tint: Color

    func body(content: Content) -> some View {
        switch style.surface {
            case .reflective:
                content.glassEffect(
                    .regular.tint(tint.opacity(style.tintOpacity)).interactive(),
                    in: Circle(),
                )
            case .matte:
                content.matteSurface(style.surface, tint: tint, in: Circle())
        }
    }
}
