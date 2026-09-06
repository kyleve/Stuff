import Testing
@testable import Throw
import UIKit

@MainActor
struct ThrowAppTests {
    @Test func appDelegateRetainsTheInjectedRuntime() {
        let runtime = ThrowApplicationRuntimeSpy()
        let delegate = AppDelegate(runtime: runtime)

        #expect(delegate.runtime === runtime)
    }

    @Test func controllerSceneLifecycleUsesTheSameRuntime() {
        let runtime = ThrowApplicationRuntimeSpy()
        let delegate = AppDelegate(runtime: runtime)
        let id = ControllerSceneID(rawValue: "controller-test")

        delegate.runtime.controllerScene(id, didReceive: .willEnterForeground)
        delegate.runtime.controllerScene(id, didReceive: .didEnterBackground)

        #expect(runtime.controllerSceneEvents == [
            RecordedControllerSceneEvent(id: id, event: .willEnterForeground),
            RecordedControllerSceneEvent(id: id, event: .didEnterBackground),
        ])
    }

    @Test func iOS27ExternalAccessoryConfigurationHasStableSceneIdentity() throws {
        let configuration = AppDelegate.externalDisplayConfiguration()
        let delegateClass = try #require(configuration.delegateClass)

        #expect(configuration.name == "Throw External Display")
        #expect(configuration.role == .windowExternalDisplayNonInteractive)
        #expect(ObjectIdentifier(delegateClass) ==
            ObjectIdentifier(ExternalDisplaySceneDelegate.self))
    }
}
