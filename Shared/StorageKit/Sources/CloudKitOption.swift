import SwiftData

/// Whether a vended SwiftData store syncs through CloudKit. A thin pass-through
/// to `ModelConfiguration.CloudKitDatabase`; forced to `.none` in `.inMemory`
/// mode (an in-memory store can't sync). Richer CloudKit configuration is out of
/// scope for now.
public enum CloudKitOption: Sendable {
    /// Local only — no CloudKit sync.
    case none
    /// Sync through the automatic (default) CloudKit container.
    case automatic

    var cloudKitDatabase: ModelConfiguration.CloudKitDatabase {
        switch self {
            case .none: .none
            case .automatic: .automatic
        }
    }
}
