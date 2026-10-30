import BroadwayUI
import SwiftUI
import ViewDocumentUI

extension EnvironmentValues {
    @Entry var whereThemeDocument: PreparedWhereThemeDocument?
    @Entry var whereThemeLayersAreActive = true
}

/// Decorations use the same production renderer in previews, cards, and Locations.
struct WhereThemeLayer: View {
    let slot: WhereThemeDocument.Slot?
    @Environment(\.whereThemeDocument) private var theme
    @Environment(\.whereThemeLayersAreActive) private var hostIsActive
    @Environment(\.scenePhase) private var scenePhase
    @MotionIsStatic private var motionIsStatic
    @State private var isVisible = false

    var body: some View {
        ZStack {
            if let slot, let layers = theme?.layers[slot] {
                ForEach(layers, id: \.document.document.root.id) { layer in
                    BViewDocumentLayer(
                        document: layer,
                        isActive: isVisible && hostIsActive && scenePhase == .active,
                        motionIsStatic: motionIsStatic,
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

extension View {
    func whereThemeBackground(
        _ slot: WhereThemeDocument.Slot?,
        cornerRadius: CGFloat = 0,
    ) -> some View {
        background {
            GeometryReader { geometry in
                WhereThemeLayer(slot: slot)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    func whereThemeOverlay(
        _ slot: WhereThemeDocument.Slot?,
        cornerRadius: CGFloat = 0,
    ) -> some View {
        overlay {
            GeometryReader { geometry in
                WhereThemeLayer(slot: slot)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

#if DEBUG
    #Preview("Empty theme layer") { WhereThemeLayer(slot: .locationsBackground).whereBroadwayRoot()
    }
#endif
