import Foundation
import Observation
import ServiceManagement

/// Registers, unregisters, and reports the app's login-item state behind
/// ``LoginItemController``. Production uses the `SMAppService.mainApp`-backed
/// implementation; tests conform a fake so no real login item is touched.
@MainActor
@_spi(Testing)
public protocol LoginItemBackend: AnyObject {
    /// Whether the app is currently registered to launch at login.
    var isRegistered: Bool { get }
    func register() throws
    func unregister() throws
}

/// The real backend: `SMAppService.mainApp`. Registering the *main app* as a
/// login item needs no helper bundle and no special entitlement.
@MainActor
final class MainAppLoginItemBackend: LoginItemBackend {
    var isRegistered: Bool {
        switch SMAppService.mainApp.status {
            case .enabled: true
            // `.requiresApproval` means the user has to flip it on in System
            // Settings before it actually launches, so it isn't "enabled" yet.
            case .notRegistered, .requiresApproval, .notFound: false
            @unknown default: false
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

/// Reflects and controls whether Foreman launches at login, wrapping
/// `SMAppService.mainApp`.
///
/// The OS owns the real state, so ``isEnabled`` is read from the backend (and
/// re-read via ``refresh()``, since the user can change it in System Settings
/// while the app runs). ``setEnabled(_:)`` registers or unregisters and then
/// re-syncs ``isEnabled`` from the backend so the observed value never lies —
/// a failed registration leaves the toggle honestly off, not falsely on.
@MainActor
@Observable
public final class LoginItemController {
    /// Whether the app is registered to launch at login. Observable so the
    /// settings toggle reflects it.
    public private(set) var isEnabled: Bool

    @ObservationIgnored private let backend: any LoginItemBackend

    public init() {
        backend = MainAppLoginItemBackend()
        isEnabled = backend.isRegistered
    }

    /// Swaps the real login-item backend for a test double.
    @_spi(Testing)
    public init(backend: any LoginItemBackend) {
        self.backend = backend
        isEnabled = backend.isRegistered
    }

    /// Re-reads the OS status; it can change outside the app (System Settings
    /// › General › Login Items).
    public func refresh() {
        isEnabled = backend.isRegistered
    }

    /// Registers or unregisters the login item, then re-syncs ``isEnabled``
    /// from the backend. Rethrows the underlying `SMAppService` error; the
    /// observed value stays honest whether it succeeds or throws.
    public func setEnabled(_ enabled: Bool) throws {
        defer { isEnabled = backend.isRegistered }
        guard enabled != isEnabled else { return }
        if enabled {
            try backend.register()
        } else {
            try backend.unregister()
        }
    }
}
