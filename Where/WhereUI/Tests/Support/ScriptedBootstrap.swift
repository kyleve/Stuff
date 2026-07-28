import Foundation
import PeriscopeCore
@_spi(Testing) import WhereCore
import WhereUI

/// A `WhereScopeAssembling` that hands back a prepared in-memory service
/// layer, so a test can drive the logged-out → logged-in path (the onboarding
/// gate, `resolveScope()`, the reset relaunch) without opening the app's
/// on-disk store or touching CoreLocation.
///
/// Counts its calls, which is how the tests assert the store is opened
/// **once**: a second `makeServices()` in one process is exactly the
/// double-open the dormant-scope handoff exists to prevent.
@MainActor
final class ScriptedBootstrap: WhereScopeAssembling {
    private let services: WhereServices

    /// What `makeLogStore()` hands back — an in-memory stand-in for the app's
    /// on-disk store, for the tests that assert *where* records are routed.
    /// `nil` (the default) means "no durable logging", which is what most tests
    /// want: nothing to open, nothing to settle.
    private let logStore: PeriscopeStore?

    /// Held open until the test releases it, so a test can hold the log store
    /// mid-open and act while the scope is still waiting for it.
    private var logStoreGate: CheckedContinuation<Void, Never>?
    private var isLogStoreGated = false

    private(set) var prepareLocationCount = 0
    private(set) var makeServicesCount = 0

    init(services: WhereServices, logStore: PeriscopeStore? = nil) {
        self.services = services
        self.logStore = logStore
    }

    func prepareLocation() {
        prepareLocationCount += 1
    }

    func makeServices() async throws -> WhereServices {
        makeServicesCount += 1
        return services
    }

    func makeLogStore() async throws -> PeriscopeStore? {
        if isLogStoreGated {
            await withCheckedContinuation { logStoreGate = $0 }
        }
        return logStore
    }

    /// Make the next `makeLogStore()` suspend until `releaseLogStore()`, so a
    /// test can reproduce the window where a scope has been set aside while its
    /// durable store is still opening.
    func gateLogStore() {
        isLogStoreGated = true
    }

    func releaseLogStore() {
        isLogStoreGated = false
        logStoreGate?.resume()
        logStoreGate = nil
    }
}

/// A `WhereScopeAssembling` whose assembly always fails, for the paths that
/// must surface an unopenable store rather than swallow it.
@MainActor
final class FailingBootstrap: WhereScopeAssembling {
    struct AssemblyFailure: Error, Equatable {}

    func prepareLocation() {}

    func makeServices() async throws -> WhereServices {
        throw AssemblyFailure()
    }

    func makeLogStore() async throws -> PeriscopeStore? {
        nil
    }
}
