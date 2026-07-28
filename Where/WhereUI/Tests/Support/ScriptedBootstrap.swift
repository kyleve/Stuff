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

    private(set) var prepareLocationCount = 0
    private(set) var makeServicesCount = 0

    init(services: WhereServices) {
        self.services = services
    }

    func prepareLocation() {
        prepareLocationCount += 1
    }

    func makeServices() async throws -> WhereServices {
        makeServicesCount += 1
        return services
    }

    /// No durable store: a test must neither write one to disk nor leave a
    /// sink attached to `Periscope.shared`.
    func makeLogStore() async throws -> PeriscopeStore? {
        nil
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
