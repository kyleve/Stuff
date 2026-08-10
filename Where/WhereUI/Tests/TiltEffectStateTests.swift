import CoreGraphics
import Testing
@testable import WhereUI

@MainActor
struct TiltEffectStateTests {
    @Test func unavailableMotionUsesTheAuthoredStaticPose() {
        let state = TiltEffectState(
            tilt: .preview,
            staticRoll: 0.3,
            staticPitch: -0.2,
            motionIsStatic: false,
        )

        #expect(state == TiltEffectState(
            roll: 0.3,
            pitch: -0.2,
            usesStaticPose: true,
        ))
    }

    @Test func lightDirectionAmplifiesAndClampsEachAxis() {
        let state = TiltEffectState(roll: 0.8, pitch: -0.75)

        #expect(state.lightDirection(travel: 2) == CGSize(width: 1, height: 1))
    }
}
