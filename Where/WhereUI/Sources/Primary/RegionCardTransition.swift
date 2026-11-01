import RegionKit
import SwiftUI

/// The native card is the zoom source; exterior ornaments remain outside its rounded clip.
struct RegionCardTransition: ViewModifier {
    let region: Region
    let namespace: Namespace.ID?
    let card: WhereStylesheet.CardStyle
    let tint: Color

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: region, in: namespace) { source in
                let elevation = card.transitionElevation(tint: tint)
                return source
                    .clipShape(RoundedRectangle(
                        cornerRadius: card.cornerRadius,
                        style: .continuous,
                    ))
                    .shadow(color: elevation.glow.color, radius: elevation.glow.radius)
                    .shadow(
                        color: elevation.lift.color,
                        radius: elevation.lift.radius,
                        y: elevation.lift.offsetY,
                    )
            }
        } else { content }
    }
}
