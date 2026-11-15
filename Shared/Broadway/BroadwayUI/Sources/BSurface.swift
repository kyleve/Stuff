import SwiftUI

/// Composes a surface without letting artwork participate in content layout or interaction.
public struct BSurface<
    SurfaceShape: Shape,
    Base: View,
    Interior: View,
    Content: View,
    Highlights: View,
    Exterior: View,
    Finish: ViewModifier,
>: View {
    private let shape: SurfaceShape
    private let base: Base
    private let interior: Interior
    private let content: Content
    private let highlights: Highlights
    private let exterior: Exterior
    private let finish: Finish

    /// Finish applies to the inner surface only. It can own material treatment or a zoom source.
    public init(
        shape: SurfaceShape,
        finish: Finish,
        @ViewBuilder base: () -> Base,
        @ViewBuilder interior: () -> Interior,
        @ViewBuilder content: () -> Content,
        @ViewBuilder highlights: () -> Highlights,
        @ViewBuilder exterior: () -> Exterior,
    ) {
        self.shape = shape
        self.base = base()
        self.interior = interior()
        self.content = content()
        self.highlights = highlights()
        self.exterior = exterior()
        self.finish = finish
    }

    public var body: some View {
        content
            .background {
                ZStack { base; interior }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .clipShape(shape)
            .overlay { highlights.allowsHitTesting(false).accessibilityHidden(true) }
            .contentShape(shape)
            .modifier(finish)
            .overlay { exterior.allowsHitTesting(false).accessibilityHidden(true) }
            // SwiftUI can include hidden overlay paint in a combined element's frame.
            // Keep its focus contour on the native surface after exterior composition.
            .contentShape(.accessibility, shape)
    }
}

#if DEBUG
    #Preview("Surface composition") {
        BSurface(shape: RoundedRectangle(cornerRadius: 20), finish: EmptyModifier()) {
            Color.orange.opacity(0.12)
        } interior: {
            Circle().fill(.orange.opacity(0.15)).padding(10)
        } content: {
            Text("Native content").font(.headline).padding(40)
        } highlights: {
            RoundedRectangle(cornerRadius: 20).stroke(.orange, lineWidth: 1)
        } exterior: {
            EmptyView()
        }
        .padding(40)
    }
#endif
