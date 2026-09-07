/// The device-local visual theme Where uses for its presentation surfaces.
///
/// Raw values are persisted in `WherePreferences` and carried across process
/// boundaries, so they are permanent storage identifiers rather than
/// customer-facing names.
public enum WhereTheme: String, CaseIterable, Codable, Hashable, Sendable {
    /// Where's default presentation theme.
    case standard

    /// A second presentation theme whose visual language may diverge later.
    case alternate
}
