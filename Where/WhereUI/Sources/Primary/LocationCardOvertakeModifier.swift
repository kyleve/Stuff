import RegionKit
import SwiftUI

/// Gives the winning Location card a passing arc and stamp-like settle while
/// the stack's layout animation moves it into first place.
struct LocationCardOvertakeModifier: ViewModifier {
    let region: Region
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
    }
}

extension View {
    func locationCardOvertakeEffect(
        region: Region,
        presentation: LocationCardsPresentationModel,
        motion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion,
    ) -> some View {
        modifier(LocationCardOvertakeModifier(
            region: region,
            presentation: presentation,
            motion: motion,
        ))
    }
}
