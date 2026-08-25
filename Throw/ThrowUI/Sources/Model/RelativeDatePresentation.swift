import Foundation
import SwiftUI
import ThrowCore

extension EnvironmentValues {
    @Entry var throwDateProvider: any DateProvider = SystemDateProvider()
}

/// Formats a date relative to an explicit clock value so previews and tests do
/// not race the wall clock while production remains locale-aware.
enum RelativeDatePresentation {
    static func string(
        for date: Date,
        relativeTo referenceDate: Date,
        locale: Locale,
        calendar: Calendar,
    ) -> String {
        let style = Date.AnchoredRelativeFormatStyle(
            anchor: date,
            presentation: .named,
            locale: locale,
            calendar: calendar,
        )
        return referenceDate.formatted(style)
    }
}
