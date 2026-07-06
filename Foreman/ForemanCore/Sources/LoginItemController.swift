import Foundation
import Observation
import ServiceManagement

/// The login-item state Foreman cares about, distilled from
/// `SMAppService.Status`.
///
/// `requiresApproval` is distinct from `notRegistered`: the app *is* registered
/// but macOS is waiting for the user to approve it in System Settings before it
/// will actually launch. Collapsing it into "off" would misreport an enabled
/// (pending) item as disabled.
public enum LoginItemStatus: Sendable, Equatable {
    case enabled
    case requiresApproval
    case notRegistered
}

/// Registers, unregisters, and reports the app's login-item state behind
/// ``LoginItemController``. Production uses the `SMAppService.mainApp`-backed
/// implementation; tests conform a fake so no real login item is touched.
@MainActor
@_spi(Testing)
public protocol LoginItemBackend: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    /// Opens System Settings › General › Login Items so the user can approve
    /// or inspect the item.
    func openSystemSettingsLoginItems()
}

/// The real backend: `SMAppService.mainApp`. Registering the *main app* as a
/// login item needs no helper bundle and no special entitlement.
@MainActor
final class MainAppLoginItemBackend: LoginItemBackend {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
            case .enabled: .enabled
            case .requiresApproval: .requiresApproval
            // `.notFound` means the service isn't registered from this bundle;
            // for the toggle that reads the same as "not registered".
            case .notRegistered, .notFound: .notRegistered
            @unknown default: .notRegistered
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Reflects and controls whether Foreman launches at login, wrapping
/// `SMAppService.mainApp`.
///
/// The OS owns the real state, so ``status`` is read from the backend (and
/// re-read via ``refresh()``, since the user can change it in System Settings
/// while the app runs). ``setEnabled(_:)`` registers or unregisters and then
/// re-syncs ``status`` from the backend so the observed value never lies — a
/// failed registration leaves the toggle honestly off, not falsely on.
@MainActor
@Observable
public final class LoginItemController {
    /// The current login-item status. Observable so the settings UI reflects
    /// it (including the pending-approval state).
    public private(set) var status: LoginItemStatus

    @ObservationIgnored private let backend: any LoginItemBackend

    /// Whether the login item is on. Includes ``LoginItemStatus/requiresApproval``:
    /// the user asked for it and it's registered — it just needs a nod in
    /// System Settings — so the toggle should read on, not off.
    public var isEnabled: Bool {
        status != .notRegistered
    }

    /// The login item is registered but macOS needs the user to approve it in
    /// System Settings before it will actually launch.
    public var needsApproval: Bool {
        status == .requiresApproval
    }

    public init() {
        backend = MainAppLoginItemBackend()
        status = backend.status
    }

    /// Swaps the real login-item backend for a test double.
    @_spi(Testing)
    public init(backend: any LoginItemBackend) {
        self.backend = backend
        status = backend.status
    }

    /// Re-reads the OS status; it can change outside the app (System Settings
    /// › General › Login Items).
    public func refresh() {
        status = backend.status
    }

    /// Registers or unregisters the login item, then re-syncs ``status`` from
    /// the backend. Rethrows the underlying `SMAppService` error; the observed
    /// value stays honest whether it succeeds or throws.
    public func setEnabled(_ enabled: Bool) throws {
        defer { status = backend.status }
        guard enabled != isEnabled else { return }
        if enabled {
            try backend.register()
        } else {
            try backend.unregister()
        }
    }

    /// Opens System Settings › General › Login Items (used to approve a
    /// pending item).
    public func openSystemSettingsLoginItems() {
        backend.openSystemSettingsLoginItems()
    }
}
