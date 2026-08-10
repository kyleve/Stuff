import SwiftUI

/// A coated-card finish — a grayscale luminance wash, a soft specular glint,
/// and an optional inset spectral rim — that slides with the device's tilt.
/// Soft-light compositing keeps the broad reflection color-neutral while the
/// narrow foil edge adds color without repainting the underlying region hue.
/// The result is clipped to the card's shape and made non-interactive.
///
/// This modifier is deliberately the observation boundary for `TiltProvider`:
/// only the lightweight overlay invalidates at the sensor's 60 Hz cadence, not
/// the card and its Canvas artwork beneath it. A caller also supplies the
/// deterministic pose used when motion must stay static, so Reduce Motion and
/// snapshot capture never depend on a live sensor reading.
struct TiltSheen<ClipShape: InsettableShape>: ViewModifier {
    var tilt: TiltProvider?
    var staticRoll: Double
    var staticPitch: Double
    var shape: ClipShape
    /// Grayscale-wash and live-glint strength, `0...1`.
    var intensity: Double = 1
    /// White-glint strength when `usesStaticPose`, `0...1`.
    var staticGlintIntensity: Double = 1
    var spectralRim: WhereStylesheet.CardStyle.Sheen.SpectralRim = .none

    @MotionIsStatic private var motionIsStatic

    func body(content: Content) -> some View {
        content.overlay {
            sheen
                .clipShape(shape)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var effectState: TiltEffectState {
        TiltEffectState(
            tilt: tilt,
            staticRoll: staticRoll,
            staticPitch: staticPitch,
            motionIsStatic: motionIsStatic,
        )
    }

    private var glintIntensity: Double {
        effectState.usesStaticPose ? staticGlintIntensity : intensity
    }

    private var sheen: some View {
        GeometryReader { proxy in
            let state = effectState
            let diagonal = max(proxy.size.width, proxy.size.height)
            let glint = UnitPoint(
                x: 0.5 + state.roll * 0.55,
                y: 0.5 - state.pitch * 0.55,
            )

            ZStack {
                // A color-neutral luminance wash that slides as the device
                // rolls, preserving the region tint beneath it.
                LinearGradient(
                    colors: Self.luminanceStops,
                    startPoint: UnitPoint(x: state.roll * 0.3, y: 0),
                    endPoint: UnitPoint(x: 1 + state.roll * 0.3, y: 1),
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

                spectralEdge(state: state)
            }
        }
    }

    private func spectralEdge(state: TiltEffectState) -> some View {
        let direction = state.lightDirection(travel: spectralRim.travel)
        let center = UnitPoint(
            x: 0.5 + direction.width * 0.58,
            y: 0.5 + direction.height * 0.58,
        )
        let angle = Angle.degrees(direction.width * 160 + direction.height * 110)
        let spectralGradient = AngularGradient(
            colors: Self.spectralStops,
            center: center,
            angle: angle,
        )
        let highlightPoints = Self.highlightPoints(direction: direction)
        let directionalHighlight = LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.58),
                .init(color: .white, location: 1),
            ],
            startPoint: highlightPoints.start,
            endPoint: highlightPoints.end,
        )

        return ZStack {
            shape
                .inset(by: spectralRim.inset)
                .strokeBorder(spectralGradient, lineWidth: spectralRim.lineWidth * 3)
                .blur(radius: spectralRim.blurRadius)
                .opacity(spectralRim.opacity * 0.42)
                .blendMode(.plusLighter)

            shape
                .inset(by: spectralRim.inset)
                .strokeBorder(spectralGradient, lineWidth: spectralRim.lineWidth)
                .opacity(spectralRim.opacity)
                .blendMode(.plusLighter)

            // A concentrated reflection crosses the light-facing edge. The
            // full spectrum still supplies the foil color, while this moving
            // peak makes small changes in device pose legible.
            shape
                .inset(by: spectralRim.inset)
                .strokeBorder(directionalHighlight, lineWidth: spectralRim.lineWidth * 1.4)
                .blur(radius: spectralRim.blurRadius * 0.35)
                .opacity(spectralRim.opacity * 0.82)
                .blendMode(.plusLighter)
        }
    }

    private static func highlightPoints(direction: CGSize) -> (start: UnitPoint, end: UnitPoint) {
        let magnitude = hypot(direction.width, direction.height)
        let unit = magnitude > 0.01
            ? CGSize(width: direction.width / magnitude, height: direction.height / magnitude)
            : CGSize(width: 0, height: 1)
        return (
            start: UnitPoint(x: 0.5 - unit.width * 0.7, y: 0.5 - unit.height * 0.7),
            end: UnitPoint(x: 0.5 + unit.width * 0.7, y: 0.5 + unit.height * 0.7),
        )
    }

    /// Alternating grayscale tones create changing light without introducing a
    /// second hue into the region's palette.
    private static var luminanceStops: [Color] {
        [.white, .gray, .black, .gray, .white]
    }

    /// A foil-like spectrum with a repeated magenta endpoint so rotating the
    /// angular gradient has no visible seam.
    private static var spectralStops: [Color] {
        [.pink, .purple, .cyan, .mint, .yellow, .orange, .pink]
    }
}

extension View {
    /// Overlay a tilt-reactive coated finish clipped to `shape`. Pass the same
    /// shape used for the card's `glassEffect` so the sheen and optional inset
    /// rim line up. The provider is observed inside the modifier to keep its
    /// frequent updates from invalidating the view that owns the card.
    func tiltSheen(
        tilt: TiltProvider?,
        staticRoll: Double,
        staticPitch: Double,
        in shape: some InsettableShape,
        intensity: Double = 1,
        staticGlintIntensity: Double = 1,
        spectralRim: WhereStylesheet.CardStyle.Sheen.SpectralRim = .none,
    ) -> some View {
        modifier(TiltSheen(
            tilt: tilt,
            staticRoll: staticRoll,
            staticPitch: staticPitch,
            shape: shape,
            intensity: intensity,
            staticGlintIntensity: staticGlintIntensity,
            spectralRim: spectralRim,
        ))
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
