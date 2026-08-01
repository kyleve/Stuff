import Observation
import WhereCore

/// Scene-local selection for the Your Year lenses, initialized from and written
/// back to the injected preferences store.
@MainActor
@Observable
final class YearModeSelection {
    private let preferences: WherePreferences

    var mode: YearViewMode {
        didSet {
            guard oldValue != mode else { return }
            preferences.yearViewMode = mode
        }
    }

    /// `initialMode` is a preview/Flyover seam. It controls the initial display
    /// without overwriting the persisted user choice merely by constructing a
    /// fixture; a later user-driven change still persists normally.
    init(preferences: WherePreferences, initialMode: YearViewMode? = nil) {
        self.preferences = preferences
        mode = initialMode ?? preferences.yearViewMode
    }
}
