import SwiftUI

/// Flat controls press ink into the card; reflective controls keep their native glass feedback.
struct CardSurfaceButtonStyle<SurfaceShape: Shape>: PrimitiveButtonStyle {
    let surface: WhereStylesheet.SurfaceTreatment
    let tint: Color
    let shape: SurfaceShape

    func makeBody(configuration: Configuration) -> some View {
        switch surface {
            case .reflective:
                PlainButtonStyle().makeBody(configuration: configuration)
            case let .matte(style):
                Button(configuration).buttonStyle(PressedTintStyle(
                    tint: tint,
                    opacity: style.pressedTintOpacity,
                    shape: shape,
                ))
        }
    }

    private struct PressedTintStyle: ButtonStyle {
        let tint: Color
        let opacity: Double
        let shape: SurfaceShape

        func makeBody(configuration: Configuration) -> some View {
            configuration.label.overlay {
                if configuration.isPressed {
                    shape.fill(tint.opacity(opacity))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}
