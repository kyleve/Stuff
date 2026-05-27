import Foundation

/// A geographic region we track presence in for purposes like state-residency
/// audits. Not US-specific: `.canada` and `.europeanUnion` are first-class.
///
/// `.other` is the catch-all for any coordinate that doesn't fall inside the
/// bundled polygons (or for manual day entries where the user wants to
/// represent "somewhere else").
///
/// The `rawValue` strings (`"california"`, `"newYork"`, …) are stable
/// data identifiers used by SwiftData, Codable, and lookup tables. They
/// are **not** user-facing — use `localizedName` for anything the UI
/// renders.
public enum Region: String, Codable, Sendable, Hashable, CaseIterable {
    case california
    case newYork
    case canada
    case europeanUnion
    case other

    /// User-facing name for this region, read from the `WhereCore`
    /// string catalog (`Resources/Localizable.xcstrings`). Falls back
    /// to the `rawValue` if the key is missing so a translator slip
    /// surfaces something readable instead of an empty string.
    ///
    /// Uses `NSLocalizedString` rather than `String(localized:)`
    /// because the key is composed at runtime (`"region.\(rawValue)"`)
    /// and `String.LocalizationValue` is designed for compile-time
    /// extractable string literals.
    public var localizedName: String {
        NSLocalizedString(
            "region.\(rawValue)",
            bundle: .module,
            comment: "User-facing name for Region.\(rawValue)",
        )
    }
}
