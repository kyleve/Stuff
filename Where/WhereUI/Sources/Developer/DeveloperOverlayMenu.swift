import SwiftUI

/// The bounded developer menu layered over the app. Its scrolling child owns the rows.
struct DeveloperOverlayMenu: View {
    let isPresented: Bool
    let corner: DeveloperOverlayModel.Corner
    let maxHeight: CGFloat
    let onOpenDestination: (DeveloperDestination) -> Void
    let onConfigureDemo: () -> Void

    var body: some View {
        ScrollView {
            DeveloperOverlayMenuContent(
                isPresented: isPresented,
                corner: corner,
                onOpenDestination: onOpenDestination,
                onConfigureDemo: onConfigureDemo,
            )
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(corner.isTop ? .top : .bottom)
        .frame(maxHeight: max(maxHeight, 0))
        .allowsHitTesting(isPresented)
        .accessibilityHidden(isPresented == false)
    }
}

#if DEBUG
    #Preview {
        DeveloperOverlayPreview(presentation: .menu)
    }
#endif
