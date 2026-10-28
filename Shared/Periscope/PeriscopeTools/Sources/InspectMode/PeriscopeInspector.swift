import Observation
import PeriscopeCore
import SwiftUI

/// The observable face of "log view mode": mirrors a `Periscope` system's
/// inspect flag both ways — toggling ``isEnabled`` writes through, and
/// direct writes to `Periscope.isInspectModeEnabled` (the source of truth)
/// flow back via its change stream — plus the store inspectable views
/// query. Inject one near the root and bind a developer-settings toggle to
/// it:
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

    @ObservationIgnored private var observationTask: Task<Void, Never>?

    /// Whether log view mode is on. Writes through to
    /// `Periscope.isInspectModeEnabled`; the no-change guards on both
    /// sides keep the mirror loop-free.
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
        observationTask = Task { [weak self, system] in
            for await enabled in system.inspectModeChanges() {
                guard let self else { return }
                if isEnabled != enabled {
                    isEnabled = enabled
                }
            }
        }
    }

    deinit {
        observationTask?.cancel()
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
