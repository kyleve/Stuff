import Foundation

/// A geographic region we track presence in for purposes like state-residency
/// audits. Not US-specific: `.canada` and `.europeanUnion` are first-class.
///
/// `.other` is the catch-all for any coordinate that doesn't fall inside the
/// bundled polygons (or for manual day entries where the user wants to
/// represent "somewhere else").
public enum Region: String, Codable, Sendable, Hashable, CaseIterable {
    case california
    case newYork
    case canada
    case europeanUnion
    case other
}

extension Region: Comparable {
    public static func < (lhs: Region, rhs: Region) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
