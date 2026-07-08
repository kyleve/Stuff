import Observation
import PeriscopeCore
import SwiftUI

/// The observable face of "log view mode": wraps a `Periscope` system's
/// inspect flag (kept in sync both ways through ``isEnabled``) plus the
/// store inspectable views query. Inject one near the root and bind a
/// developer-settings toggle to it:
///
/// ```swift
/// RootView()
///     .periscopeInspector(inspector)
///
/// // in developer settings:
/// Toggle("Log View Mode", isOn: $inspector.isEnabled)
/// ```
@MainActor
@Observable
public final class PeriscopeInspector {
    public let system: Periscope
    public let store: PeriscopeStore

    /// Whether log view mode is on. Writes through to
    /// `Periscope.isInspectModeEnabled`, the flag's source of truth for
    /// non-UI callers.
    public var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            system.isInspectModeEnabled = isEnabled
        }
    }

    public init(system: Periscope, store: PeriscopeStore) {
        self.system = system
        self.store = store
        isEnabled = system.isInspectModeEnabled
    }
}

extension EnvironmentValues {
    /// The inspector wired by ``SwiftUICore/View/periscopeInspector(_:)``;
    /// `nil` where none was injected (inspectable views then render
    /// unchanged).
    @Entry public var periscopeInspector: PeriscopeInspector?
}

extension View {
    /// Make ``PeriscopeInspector`` available to every `logInspectable` view
    /// below — typically applied once at the app root, gated to developer
    /// builds.
    public func periscopeInspector(_ inspector: PeriscopeInspector) -> some View {
        environment(\.periscopeInspector, inspector)
    }
}
