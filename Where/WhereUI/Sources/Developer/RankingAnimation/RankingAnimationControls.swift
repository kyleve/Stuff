#if DEBUG
    import SwiftUI

    /// Session-only sliders for the container-owned overtake motion.
    struct RankingAnimationControls: View {
        @Binding var motion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion
        let reset: () -> Void

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Section {
                CardDesignerDoubleControl(
                    title: .rankingAnimationDuration,
                    value: $motion.duration,
                    range: WhereStylesheet.LocationCardStackStyle.OvertakeMotion.durationRange,
                    step: 0.05,
                )
                CardDesignerDoubleControl(
                    title: .rankingAnimationBounce,
                    value: $motion.bounce,
                    range: WhereStylesheet.LocationCardStackStyle.OvertakeMotion.bounceRange,
                    step: 0.01,
                )
                CardDesignerCGFloatControl(
                    title: .rankingAnimationLateralArc,
                    value: $motion.lateralArc,
                    range: WhereStylesheet.LocationCardStackStyle.OvertakeMotion.lateralArcRange,
                    step: 1,
                )
                CardDesignerCGFloatControl(
                    title: .rankingAnimationLiftScale,
                    value: $motion.liftScale,
                    range: WhereStylesheet.LocationCardStackStyle.OvertakeMotion.liftScaleRange,
                    step: 0.005,
                )
                CardDesignerDoubleControl(
                    title: .rankingAnimationRotation,
                    value: $motion.rotationDegrees,
                    range: WhereStylesheet.LocationCardStackStyle.OvertakeMotion.rotationRange,
                    step: 0.25,
                )
                CardDesignerCGFloatControl(
                    title: .rankingAnimationSettleScale,
                    value: $motion.settleScale,
                    range: WhereStylesheet.LocationCardStackStyle.OvertakeMotion.settleScaleRange,
                    step: 0.005,
                )
            } header: {
                CardDesignerSectionHeader(
                    title: .rankingAnimationMotion,
                    reset: reset,
                )
            } footer: {
                if reduceMotion {
                    Text(String(localized: .rankingAnimationReduceMotionFooter))
                }
            }
        }
    }

    #Preview {
        @Previewable @State var motion = WhereStylesheet.LocationCardStackStyle.OvertakeMotion
            .standard
        Form {
            RankingAnimationControls(motion: $motion, reset: {})
        }
    }
#endif
