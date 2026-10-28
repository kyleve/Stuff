import PeriscopeCore

extension LogLevel {
    /// Capitalized name shown in badges and the level filter.
    var displayName: String {
        name.capitalized
    }

    /// Uppercased label used in badges and export text.
    var badgeLabel: String {
        name.uppercased()
    }
}
