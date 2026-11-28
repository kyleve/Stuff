import SwiftUI

/// A color-neutral sheen overlay — a grayscale luminance wash plus a soft
/// specular glint — that slides with the device's tilt, the way light catches a
/// coated card. Soft-light compositing preserves the card's underlying region
/// hue, then the result is clipped to the card's shape and made non-interactive.
///
/// This modifier is deliberately the observation boundary for `TiltProvider`:
/// only the lightweight overlay invalidates at the sensor's 60 Hz cadence, not
/// the card and its Canvas artwork beneath it. A caller also supplies the
/// deterministic pose used when motion must stay static, so Reduce Motion and
/// snapshot capture never depend on a live sensor reading.
struct TiltSheen<ClipShape: Shape>: ViewModifier {
    var tilt: TiltProvider?
    var staticRoll: Double
    var staticPitch: Double
    var shape: ClipShape
    /// Grayscale-wash and live-glint strength, `0...1`.
    var intensity: Double = 1
    /// White-glint strength when `usesStaticPose`, `0...1`.
    var staticGlintIntensity: Double = 1

    @MotionIsStatic private var motionIsStatic

    func body(content: Content) -> some View {
        content.overlay {
            TiltSheenHighlight(
                activeRoll: activeRoll,
                activePitch: activePitch,
                intensity: intensity,
                glintIntensity: glintIntensity,
            )
            .clipShape(shape)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Tilt actually used to place the highlight. Static-motion contexts use
    /// the caller's deterministic pose so the sheen stays put.
    private var activeRoll: Double {
        usesStaticPose ? staticRoll.clamped : (tilt?.roll ?? staticRoll).clamped
    }

    private var activePitch: Double {
        usesStaticPose ? staticPitch.clamped : (tilt?.pitch ?? staticPitch).clamped
    }

    private var usesStaticPose: Bool {
        motionIsStatic || tilt?.hasLiveSample != true
    }

    private var glintIntensity: Double {
        usesStaticPose ? staticGlintIntensity : intensity
    }
}

private struct TiltSheenHighlight: View {
    let activeRoll: Double
    let activePitch: Double
    let intensity: Double
    let glintIntensity: Double

    var body: some View {
        GeometryReader { proxy in
            let diagonal = max(proxy.size.width, proxy.size.height)
            let glint = UnitPoint(
                x: 0.5 + activeRoll * 0.55,
                y: 0.5 - activePitch * 0.55,
            )

            ZStack {
                // A color-neutral luminance wash that slides as the device
                // rolls, preserving the region tint beneath it.
                LuminanceWash(roll: activeRoll, intensity: intensity)

                // Specular glint that tracks the tilt like a moving light.
                SpecularGlint(center: glint, diagonal: diagonal, intensity: glintIntensity)
            }
        }
    }
}

private struct LuminanceWash: View {
    let roll: Double
    let intensity: Double

    var body: some View {
        LinearGradient(
            colors: [.white, .gray, .black, .gray, .white],
            startPoint: UnitPoint(x: roll * 0.3, y: 0),
            endPoint: UnitPoint(x: 1 + roll * 0.3, y: 1),
        )
        .opacity(0.28 * intensity)
        .blendMode(.softLight)
    }
}

private struct SpecularGlint: View {
    let center: UnitPoint
    let diagonal: CGFloat
    let intensity: Double

    var body: some View {
        RadialGradient(
            colors: [
                Color.white.opacity(0.85 * intensity),
                Color.white.opacity(0),
            ],
            center: center,
            startRadius: 0,
            endRadius: diagonal * 0.75,
        )
        .blendMode(.softLight)
    }
}

extension View {
    /// Overlay a tilt-reactive grayscale sheen clipped to `shape`. Pass the same
    /// shape used for the card's `glassEffect` so the sheen lines up. The
    /// provider is observed inside the modifier to keep its frequent updates
    /// from invalidating the view that owns the card.
    func tiltSheen(
        tilt: TiltProvider?,
        staticRoll: Double,
        staticPitch: Double,
        in shape: some Shape,
        intensity: Double = 1,
        staticGlintIntensity: Double = 1,
    ) -> some View {
        modifier(TiltSheen(
            tilt: tilt,
            staticRoll: staticRoll,
            staticPitch: staticPitch,
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
                tilt: nil,
                staticRoll: 0.4,
                staticPitch: -0.2,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous),
                staticGlintIntensity: 1,
            )
            .padding()
    }
#endif
