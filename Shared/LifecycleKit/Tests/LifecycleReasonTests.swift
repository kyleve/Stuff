@testable import LifecycleKit
import Testing

struct LifecycleReasonTests {
    @Test func foregroundBuildsAViewTreeAndGatesToForegroundSteps() {
        #expect(!LifecycleReason.userForeground.buildsNoViewTree)
        #expect(LifecycleReason.userForeground.modeSet == .foreground)
    }

    @Test func backgroundBuildsNoViewTreeAndGatesToBackgroundSteps() {
        let reason = LifecycleReason.background(.location)
        #expect(reason.buildsNoViewTree)
        #expect(reason.modeSet == .background)
    }

    @Test func undeterminedBehavesLikeBackgroundUntilPromoted() {
        // Until a scene proves the launch is user-visible, `.undetermined`
        // renders no view tree and runs only the background-safe step subset —
        // servicing a possible headless wake without claiming a cause.
        #expect(LifecycleReason.undetermined.buildsNoViewTree)
        #expect(LifecycleReason.undetermined.modeSet == .background)
    }
}
