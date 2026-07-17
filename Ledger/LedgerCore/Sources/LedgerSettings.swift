import Foundation
import Observation

/// The settings node of the Ledger model tree: which team member's spend to
/// show and how often to refresh it. The Admin API key is *not* here — it
/// lives in the Keychain (see ``KeychainStore``); this holds only the
/// non-secret preferences that persist as JSON.
///
/// Mutations notify the injected funnel so the owning tree persists on any
/// change; reassigning an equal value is a no-op.
@MainActor
@Observable
public final class LedgerSettings {
    /// The email of the team member whose spend Ledger displays. `nil` until
    /// the user sets it in Settings; a spend fetch with no email surfaces
    /// ``LedgerServices/LoadError/missingCredentials``.
    public var teamMemberEmail: String? {
        didSet {
            guard oldValue != teamMemberEmail else { return }
            onPersistentChange()
        }
    }

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
        teamMemberEmail: String?,
        refreshInterval: TimeInterval,
        onPersistentChange: @escaping @MainActor () -> Void,
    ) {
        self.teamMemberEmail = teamMemberEmail
        self.refreshInterval = refreshInterval
        self.onPersistentChange = onPersistentChange
    }
}
