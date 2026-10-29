import RegionKit

/// A stable namespace for one calendar's device-local zoom preference.
/// Raw values are storage identifiers and must survive Swift-side renames.
public struct CalendarZoomKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let year = Self(rawValue: "year")

    public static func region(_ region: Region) -> Self {
        Self(rawValue: "region.\(region.rawValue)")
    }
}
