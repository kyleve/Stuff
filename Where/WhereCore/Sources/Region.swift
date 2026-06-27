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
    /// string catalog via ``LocalizedStrings/Region``.
    ///
    /// Each case maps to a literal catalog key (rather than a runtime-composed
    /// `"region.\(rawValue)"`) so Xcode's string-catalog extraction tooling and
    /// the repo's `./localize` script can statically find every key. Adding a
    /// new region case is intentionally a compile error here until you add a
    /// matching ``LocalizedStrings/Region`` member and catalog entry.
    public var localizedName: String {
        switch self {
            case .california:
                LocalizedStrings.Region.california.localized
            case .newYork:
                LocalizedStrings.Region.newYork.localized
            case .canada:
                LocalizedStrings.Region.canada.localized
            case .europeanUnion:
                LocalizedStrings.Region.europeanUnion.localized
            case .other:
                LocalizedStrings.Region.other.localized
        }
    }
}
