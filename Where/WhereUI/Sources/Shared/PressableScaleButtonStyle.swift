import SwiftUI

/// A button style that gives its label a physical, tactile press: it shrinks
/// quickly under the finger and springs back with a little bounce on release.
/// Used for the Primary region cards so tapping into a region's calendar feels
/// like pressing a real object. Honors Reduce Motion by skipping the scale.
struct PressableScaleButtonStyle: ButtonStyle {
    /// How far the label shrinks while pressed (1 = no shrink).
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        PressableScale(configuration: configuration, pressedScale: pressedScale)
    }

    /// A nested view so the scale can read Reduce Motion from the environment —
    /// a `ButtonStyle` value itself can't hold `@Environment` properties.
    private struct PressableScale: View {
        let configuration: ButtonStyleConfiguration
        let pressedScale: CGFloat

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(scale)
                .animation(pressAnimation, value: configuration.isPressed)
        }

        private var scale: CGFloat {
            guard !reduceMotion else { return 1 }
            return configuration.isPressed ? pressedScale : 1
        }

        /// A snappy ease-out shrink on press-down, then a bouncier spring back
        /// up on release.
        private var pressAnimation: Animation {
            configuration.isPressed
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.4, dampingFraction: 0.5)
        }
    }
}

#if DEBUG
    #Preview {
        Button {} label: {
            Text(verbatim: "Press me")
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    .tint,
                    in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.card),
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(PressableScaleButtonStyle())
        .padding()
    }
#endif
