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

    @Test func appLifecycleIsForwardedToTheSameRuntime() {
        let runtime = ThrowApplicationRuntimeSpy()
        let delegate = AppDelegate(runtime: runtime)

        delegate.applicationDidEnterBackground(UIApplication.shared)
        delegate.applicationWillEnterForeground(UIApplication.shared)

        #expect(runtime.backgroundCount == 1)
        #expect(runtime.foregroundCount == 1)
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
