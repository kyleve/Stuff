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
                MatteButton(
                    configuration: configuration,
                    tint: tint,
                    opacity: style.pressedTintOpacity,
                    shape: shape,
                )
        }
    }

    private struct MatteButton: View {
        let configuration: PrimitiveButtonStyleConfiguration
        let tint: Color
        let opacity: Double
        let shape: SurfaceShape

        var body: some View {
            Button(configuration).buttonStyle(PressedTintStyle(
                tint: tint,
                opacity: opacity,
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

#if DEBUG
    import SnapshotKit

    #Preview { LocationsView.snapshotPreviews }
#endif
