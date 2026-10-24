import Testing
@testable import Throw
import ThrowUI
import UIKit

@MainActor
struct ExternalDisplaySceneDelegateTests {
    @Test func platformHandoffUsesTheDelegateOwnedRuntime() throws {
        let runtime = ThrowApplicationRuntimeSpy()
        let delegate = AppDelegate(runtime: runtime)

        let resolved = try #require(ExternalDisplaySceneDelegate.runtime(from: delegate))

        #expect(resolved === runtime)
    }

    @Test func unrelatedApplicationDelegateCannotCreateARuntime() {
        #expect(ExternalDisplaySceneDelegate.runtime(from: UnrelatedDelegate()) == nil)
    }

    @Test func projectionOutputLifecycleUsesTheInjectedRuntime() {
        let runtime = ThrowApplicationRuntimeSpy()
        let delegate = ExternalDisplaySceneDelegate()
        let output = ProjectionOutput.externalDisplay(
            ProjectionOutputID(rawValue: "external-lifecycle-test"),
        )

        delegate.connectProjectionOutput(output, runtime: runtime) { _ in }
        #expect(runtime.connectedOutputs == [output])

        delegate.disconnectProjectionOutput()
        delegate.disconnectProjectionOutput()
        #expect(runtime.disconnectedOutputs == [output])
    }
}

@MainActor
private final class UnrelatedDelegate: NSObject, UIApplicationDelegate {}
