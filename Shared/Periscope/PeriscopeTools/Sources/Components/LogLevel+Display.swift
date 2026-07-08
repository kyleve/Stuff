import PeriscopeCore
import SwiftUI

extension LogLevel {
    /// Capitalized name shown in badges and the level filter.
    var displayName: String {
        name.capitalized
    }

    /// Uppercased label used in badges and export text.
    var badgeLabel: String {
        name.uppercased()
    }

    /// Tint escalating with severity — banded so custom levels inherit a
    /// sensible color from their position in the ladder.
    var tint: Color {
        switch severity {
            case ..<LogLevel.info.severity: .gray
            case ..<LogLevel.notice.severity: .blue
            case ..<LogLevel.warning.severity: .teal
            case ..<LogLevel.error.severity: .yellow
            case ..<LogLevel.fault.severity: .orange
            default: .red
        }
    }
}
