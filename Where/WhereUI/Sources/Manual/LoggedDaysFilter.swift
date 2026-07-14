import WhereCore

/// Which manual entries the logged-days list shows: additive backfills
/// ("Logged"), authoritative overrides ("Overridden"), or both. A pure
/// presentation filter over the already-loaded entries.
enum LoggedDaysFilter: CaseIterable, Identifiable {
    case all
    case logged
    case overridden

    var id: Self {
        self
    }

    /// Segmented-control label. Reuses the row "kind" strings for logged/
    /// overridden so the tag and the filter never drift apart.
    var title: String {
        switch self {
            case .all: Strings.loggedDaysFilterAll
            case .logged: Strings.loggedDaysKindLogged
            case .overridden: Strings.loggedDaysKindOverridden
        }
    }

    /// Whether `day` passes this filter.
    func matches(_ day: DayPresence) -> Bool {
        switch self {
            case .all: true
            case .logged: !day.isAuthoritative
            case .overridden: day.isAuthoritative
        }
    }
}
