import RegionKit
import SwiftUI

/// Gives the winning Location card a passing arc and stamp-like settle while
/// the stack's layout animation moves it into first place.
struct LocationCardOvertakeModifier: ViewModifier {
    let region: Region
    let namespace: Namespace.ID
    let presentation: LocationCardsPresentationModel
    let motion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion

    private struct AnimationValues {
        var lateralOffset: CGFloat = 0
        var scale: CGFloat = 1
        var rotationDegrees = 0.0
        var opacity = 1.0
    }

    private var isLatestWinner: Bool {
        presentation.latestOvertake?.winner == region
    }

    func body(content: Content) -> some View {
        content
            // Resolve the card's position and size at this boundary. Without a
            // geometry group, SwiftUI pushes the stack's animated reorder down
            // to the card's individual drawing leaves; the outer glass can jump
            // to its destination while an inner layer scales into place.
            .geometryGroup()
            // Liquid Glass and Canvas artwork otherwise remain separate render
            // layers. Flatten the complete card before applying the passing
            // transform so its glass, microprint, and foreground stay aligned.
            .compositingGroup()
            .zIndex(isLatestWinner ? 1 : 0)
            .keyframeAnimator(
                initialValue: AnimationValues(),
                trigger: presentation.overtakeTrigger(for: region),
            ) { content, values in
                content
                    .offset(x: values.lateralOffset)
                    .scaleEffect(values.scale)
                    .rotationEffect(.degrees(values.rotationDegrees))
                    .opacity(values.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.lateralOffset) {
                    CubicKeyframe(motion.lateralArc, duration: motion.duration * 0.3)
                    CubicKeyframe(0, duration: motion.duration * 0.3)
                    LinearKeyframe(0, duration: motion.duration * 0.4)
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(motion.liftScale, duration: motion.duration * 0.55)
                    CubicKeyframe(motion.settleScale, duration: motion.duration * 0.15)
                    SpringKeyframe(1, duration: motion.duration * 0.3, spring: .bouncy)
                }
                KeyframeTrack(\.rotationDegrees) {
                    CubicKeyframe(motion.rotationDegrees, duration: motion.duration * 0.3)
                    CubicKeyframe(0, duration: motion.duration * 0.3)
                    LinearKeyframe(0, duration: motion.duration * 0.4)
                }
                KeyframeTrack(\.opacity) {
                    CubicKeyframe(motion.minimumOpacity, duration: motion.duration * 0.35)
                    CubicKeyframe(1, duration: motion.duration * 0.65)
                }
            }
            // A ranked `ForEach` legitimately changes hierarchy order. Give
            // both the complete card and the separately rendered Liquid Glass
            // effect the region's identity so neither materializes as a new
            // bottom card on the next reversal.
            .matchedGeometryEffect(id: region, in: namespace, properties: .position)
            .glassEffectID(region, in: namespace)
    }
}

extension View {
    func locationCardOvertakeEffect(
        region: Region,
        namespace: Namespace.ID,
        presentation: LocationCardsPresentationModel,
        motion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion,
    ) -> some View {
        modifier(LocationCardOvertakeModifier(
            region: region,
            namespace: namespace,
            presentation: presentation,
            motion: motion,
        ))
    }
}
