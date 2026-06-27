import StuffCore
import SwiftUI

extension Text {
    /// Build a `Text` from a deferred ``LocalizedString``, resolving it at the
    /// point of display — e.g. `Text(localized: .primary.emptyDescription)`.
    ///
    /// Prefer this over `Text(someString.localized)` at call sites so the
    /// resolution seam stays in one place — it's where a future
    /// Environment-driven locale override will read the locale from.
    public init(localized string: LocalizedString, _ config: LocalizationConfig? = nil) {
        self.init(string.localized(config))
    }
}
