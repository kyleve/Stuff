import StuffCore
import SwiftUI

extension Text {
    /// Build a `Text` from a deferred ``LocalizedString``, resolving it at the
    /// point of display.
    ///
    /// Prefer this over `Text(someString.localized())` at call sites so the
    /// resolution seam stays in one place — it's where a future
    /// Environment-driven locale override will read the locale from.
    public static func localized(
        _ string: LocalizedString,
        _ config: LocalizationConfig? = nil,
    ) -> Text {
        Text(string.localized(config))
    }
}
