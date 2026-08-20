#if DEBUG
    import SwiftUI
    import Testing
    import UIKit
    @testable import WhereUI

    @MainActor
    struct RankingAnimationControlsTests {
        @Test func hostsEveryStandardControlWithinItsRange() {
            let motion = WhereStylesheet.LocationCardStackStyle.OvertakeMotion.standard
            let controller = UIHostingController(
                rootView: Form {
                    RankingAnimationControls(motion: .constant(motion), reset: {})
                },
            )

            #expect(controller.view != nil)
            #expect(WhereStylesheet.LocationCardStackStyle.OvertakeMotion.durationRange.contains(
                motion.duration,
            ))
            #expect(WhereStylesheet.LocationCardStackStyle.OvertakeMotion.bounceRange.contains(
                motion.bounce,
            ))
            #expect(WhereStylesheet.LocationCardStackStyle.OvertakeMotion.lateralArcRange.contains(
                motion.lateralArc,
            ))
            #expect(WhereStylesheet.LocationCardStackStyle.OvertakeMotion.liftScaleRange.contains(
                motion.liftScale,
            ))
            #expect(WhereStylesheet.LocationCardStackStyle.OvertakeMotion.rotationRange.contains(
                motion.rotationDegrees,
            ))
            #expect(WhereStylesheet.LocationCardStackStyle.OvertakeMotion.settleScaleRange.contains(
                motion.settleScale,
            ))
        }
    }
#endif
