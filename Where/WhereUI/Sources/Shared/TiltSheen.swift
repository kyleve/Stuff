import SwiftUI

/// A color-neutral sheen overlay — a grayscale luminance wash plus a soft
/// specular glint — that slides with the device's tilt, the way light catches a
/// coated card. Soft-light compositing preserves the card's underlying region
/// hue, then the result is clipped to the card's shape and made non-interactive.
///
/// Driven by normalized `roll`/`pitch` (see `TiltProvider`). A caller also
/// supplies the deterministic pose used when motion must stay static, so Reduce
/// Motion and snapshot capture never depend on a live sensor reading.
struct TiltSheen<ClipShape: Shape>: ViewModifier {
    var roll: Double
    var pitch: Double
    var staticRoll: Double
    var staticPitch: Double
    var isStatic: Bool
    var shape: ClipShape
    /// Grayscale-wash and live-glint strength, `0...1`.
    var intensity: Double = 1
    /// White-glint strength when `usesStaticPose`, `0...1`.
    var staticGlintIntensity: Double = 1

    @MotionIsStatic private var motionIsStatic

    func body(content: Content) -> some View {
        content.overlay {
            sheen
                .clipShape(shape)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Tilt actually used to place the highlight. Static-motion contexts use
    /// the caller's deterministic pose so the sheen stays put.
    private var activeRoll: Double {
        usesStaticPose ? staticRoll.clamped : roll.clamped
    }

    private var activePitch: Double {
        usesStaticPose ? staticPitch.clamped : pitch.clamped
    }

    private var usesStaticPose: Bool {
        isStatic || motionIsStatic
    }

    private var glintIntensity: Double {
        usesStaticPose ? staticGlintIntensity : intensity
    }

    private var sheen: some View {
        GeometryReader { proxy in
            let diagonal = max(proxy.size.width, proxy.size.height)
            let glint = UnitPoint(
                x: 0.5 + activeRoll * 0.55,
                y: 0.5 - activePitch * 0.55,
            )

            ZStack {
                // A color-neutral luminance wash that slides as the device
                // rolls, preserving the region tint beneath it.
                LinearGradient(
                    colors: Self.luminanceStops,
                    startPoint: UnitPoint(x: activeRoll * 0.3, y: 0),
                    endPoint: UnitPoint(x: 1 + activeRoll * 0.3, y: 1),
                )
                .opacity(0.28 * intensity)
                .blendMode(.softLight)

                // Specular glint that tracks the tilt like a moving light.
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.85 * glintIntensity),
                        Color.white.opacity(0),
                    ],
                    center: glint,
                    startRadius: 0,
                    endRadius: diagonal * 0.75,
                )
                .blendMode(.softLight)
            }
        }
    }

    /// Alternating grayscale tones create changing light without introducing a
    /// second hue into the region's palette.
    private static var luminanceStops: [Color] {
        [.white, .gray, .black, .gray, .white]
    }
}

extension View {
    /// Overlay a tilt-reactive grayscale sheen clipped to `shape`. Pass the same
    /// shape used for the card's `glassEffect` so the sheen lines up.
    func tiltSheen(
        roll: Double,
        pitch: Double,
        staticRoll: Double,
        staticPitch: Double,
        isStatic: Bool,
        in shape: some Shape,
        intensity: Double = 1,
        staticGlintIntensity: Double = 1,
    ) -> some View {
        modifier(TiltSheen(
            roll: roll,
            pitch: pitch,
            staticRoll: staticRoll,
            staticPitch: staticPitch,
            isStatic: isStatic,
            shape: shape,
            intensity: intensity,
            staticGlintIntensity: staticGlintIntensity,
        ))
    }
}

extension Double {
    /// Clamped to `-1...1` so out-of-range gravity readings can't fling the
    /// glint off the card.
    fileprivate var clamped: Double {
        min(1, max(-1, self))
    }
}

#if DEBUG
    #Preview {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.indigo.gradient)
            .frame(width: 320, height: 180)
            .tiltSheen(
                roll: 0.4,
                pitch: -0.2,
                staticRoll: 0.4,
                staticPitch: -0.2,
                isStatic: false,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous),
                staticGlintIntensity: 1,
            )
            .padding()
    }
#endif
