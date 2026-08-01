import Foundation

/// The user's preferred lens for the Your Year screen.
///
/// Raw values are persisted in ``WherePreferences`` and are therefore stable
/// storage identifiers: rename a Swift case only while preserving its raw value.
public enum YearViewMode: String, CaseIterable, Hashable, Sendable {
    case calendar
    case timeline
    case breakdown
    case heatmap
}
