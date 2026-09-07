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
        let isWinner = isLatestWinner
        let releasedMotion = presentation.latestOvertake?.motion ?? motion
        GlassEffectContainer {
            content
                // This is a stable ranked view, not a newly inserted glass
                // shape. Disable Liquid Glass's own materialization transition.
                .glassEffectTransition(.identity)
        }
        // Resolve the complete one-card glass container as one geometry
        // before the authored rank layout and flourish transform it.
        .geometryGroup()
        .zIndex(isWinner ? 1 : 0)
        .keyframeAnimator(
            initialValue: AnimationValues(),
            trigger: presentation.overtakeTrigger,
        ) { content, values in
            content
                .offset(x: values.lateralOffset)
                .scaleEffect(values.scale)
                .rotationEffect(.degrees(values.rotationDegrees))
                .opacity(values.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.lateralOffset) {
                CubicKeyframe(
                    isWinner ? releasedMotion.lateralArc : 0,
                    duration: releasedMotion.duration * 0.3,
                )
                CubicKeyframe(0, duration: releasedMotion.duration * 0.3)
                LinearKeyframe(0, duration: releasedMotion.duration * 0.4)
            }
            KeyframeTrack(\.scale) {
                CubicKeyframe(
                    isWinner ? releasedMotion.liftScale : 1,
                    duration: releasedMotion.duration * 0.55,
                )
                CubicKeyframe(
                    isWinner ? releasedMotion.settleScale : 1,
                    duration: releasedMotion.duration * 0.15,
                )
                SpringKeyframe(
                    1,
                    duration: releasedMotion.duration * 0.3,
                    spring: Spring(
                        duration: releasedMotion.duration * 0.3,
                        bounce: releasedMotion.bounce,
                    ),
                )
            }
            KeyframeTrack(\.rotationDegrees) {
                CubicKeyframe(
                    isWinner ? releasedMotion.rotationDegrees : 0,
                    duration: releasedMotion.duration * 0.3,
                )
                CubicKeyframe(0, duration: releasedMotion.duration * 0.3)
                LinearKeyframe(0, duration: releasedMotion.duration * 0.4)
            }
            KeyframeTrack(\.opacity) {
                CubicKeyframe(
                    isWinner ? releasedMotion.minimumOpacity : 1,
                    duration: releasedMotion.duration * 0.35,
                )
                CubicKeyframe(1, duration: releasedMotion.duration * 0.65)
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
