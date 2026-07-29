import Foundation
import WhereCore

/// Memory-backed preferences for any suite that needs them.
///
/// `WherePreferences` deliberately has no default store, so every test names
/// one — this is that one place, rather than the same in-memory builder
/// copy-pasted into each suite. Nothing here may touch the host's real
/// `UserDefaults`: those are process-wide and survive the run, so a test that
/// wrote to them would leak into its siblings and into the next launch.
func makePreferences() -> WherePreferences {
    WherePreferences(store: InMemoryKeyValueStore())
}
