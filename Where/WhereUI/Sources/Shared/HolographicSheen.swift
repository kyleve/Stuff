import SwiftUI

/// A holographic "foil" sheen overlay — a translucent rainbow wash plus a
/// bright specular glint — that slides with the device's tilt, the way light
/// catches the hologram on a passport page or a foil trading card. Composited
/// over whatever it modifies (typically a Liquid Glass card), clipped to the
/// card's shape, and non-interactive.
///
/// Driven by normalized `roll`/`pitch` (see `TiltProvider`); at the neutral
/// zero it renders a gentle static sheen, so it degrades cleanly on hardware
/// without motion. Honors Reduce Motion by pinning the glint to a fixed offset
/// instead of tracking the device.
struct HolographicSheen<ClipShape: Shape>: ViewModifier {
    var roll: Double
    var pitch: Double
    var shape: ClipShape
    var tint: Color = .white
    /// Overall strength of the effect, `0...1`.
    var intensity: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            sheen
                .clipShape(shape)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Tilt actually used to place the highlight. Reduce Motion replaces the
    /// live values with a fixed, gentle diagonal so the sheen stays put.
    private var activeRoll: Double {
        reduceMotion ? 0.18 : roll.clamped
    }

    private var activePitch: Double {
        reduceMotion ? -0.12 : pitch.clamped
    }

    private var sheen: some View {
        GeometryReader { proxy in
            let diagonal = max(proxy.size.width, proxy.size.height)
            let glint = UnitPoint(
                x: 0.5 + activeRoll * 0.55,
                y: 0.5 - activePitch * 0.55,
            )

            ZStack {
                // Rainbow foil that slides laterally as the device rolls.
                LinearGradient(
                    colors: Self.foilHues,
                    startPoint: UnitPoint(x: activeRoll * 0.3, y: 0),
                    endPoint: UnitPoint(x: 1 + activeRoll * 0.3, y: 1),
                )
                .opacity(0.28 * intensity)
                .blendMode(.plusLighter)

                // Specular glint that tracks the tilt like a moving light.
                RadialGradient(
                    colors: [tint.opacity(0.85 * intensity), tint.opacity(0)],
                    center: glint,
                    startRadius: 0,
                    endRadius: diagonal * 0.75,
                )
                .blendMode(.plusLighter)
            }
        }
    }

    /// Translucent rainbow used for the foil wash.
    private static var foilHues: [Color] {
        [.pink, .purple, .blue, .cyan, .green, .yellow, .orange]
    }
}

extension View {
    /// Overlay a tilt-reactive holographic sheen clipped to `shape`. Pass the
    /// same shape used for the card's `glassEffect` so the sheen lines up.
    func holographicSheen(
        roll: Double,
        pitch: Double,
        in shape: some Shape,
        tint: Color = .white,
        intensity: Double = 1,
    ) -> some View {
        modifier(HolographicSheen(
            roll: roll,
            pitch: pitch,
            shape: shape,
            tint: tint,
            intensity: intensity,
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
            .holographicSheen(
                roll: 0.4,
                pitch: -0.2,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous),
            )
            .padding()
    }
#endif
