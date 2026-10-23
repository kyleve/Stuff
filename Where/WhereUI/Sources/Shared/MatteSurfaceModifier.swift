import SwiftUI

/// Renders opaque paper beneath existing content and artwork without a material layer.
struct MatteSurfaceModifier<SurfaceShape: InsettableShape>: ViewModifier {
    let treatment: WhereStylesheet.SurfaceTreatment
    let tint: Color
    let shape: SurfaceShape

    func body(content: Content) -> some View {
        switch treatment {
            case .reflective:
                content
            case let .matte(style):
                content
                    .background(shape.fill(style.fill.color(tint: tint)))
                    .clipShape(shape)
                    .overlay {
                        // Expand before stroking inward so the outline blends with the surrounding
                        // background.
                        shape.inset(by: -style.outline.width).strokeBorder(
                            tint.opacity(style.outline.opacity),
                            lineWidth: style.outline.width,
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                    .contentShape(shape)
                    .shadow(
                        color: style.shadow.color,
                        radius: style.shadow.radius,
                        y: style.shadow.offsetY,
                    )
        }
    }
}

extension View {
    func matteSurface(
        _ treatment: WhereStylesheet.SurfaceTreatment,
        tint: Color,
        in shape: some InsettableShape,
    ) -> some View {
        modifier(MatteSurfaceModifier(treatment: treatment, tint: tint, shape: shape))
    }
}
