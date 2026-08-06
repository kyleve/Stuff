import Foundation
import Observation

/// The settings node of the Ledger model tree: how often to refresh. Identity
/// comes from the Cursor session token (auto-detected from the local Cursor
/// app, or pasted and kept in the Keychain), so there's no email or key here —
/// only the non-secret preference that persists as JSON.
///
/// Mutations notify the injected funnel so the owning tree persists on any
/// change; reassigning an equal value is a no-op.
@MainActor
@Observable
public final class LedgerSettings {
    /// How often the spend is auto-refreshed while the app runs.
    public var refreshInterval: TimeInterval {
        didSet {
            guard oldValue != refreshInterval else { return }
            onPersistentChange()
        }
    }

    private let onPersistentChange: @MainActor () -> Void

    /// Initial values are the saved configuration; assigning them here does
    /// not invoke the funnel.
    public init(
        refreshInterval: TimeInterval,
        onPersistentChange: @escaping @MainActor () -> Void,
    ) {
        self.refreshInterval = refreshInterval
        self.onPersistentChange = onPersistentChange
    }
}
