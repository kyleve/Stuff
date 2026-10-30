import RegionKit
import SwiftUI

struct WhereCardFinish: ViewModifier {
    let surface: RegionCardSurface
    let transition: RegionCardTransition
    func body(content: Content) -> some View {
        content.modifier(surface).modifier(transition)
    }
}
