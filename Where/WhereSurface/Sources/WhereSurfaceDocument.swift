import Foundation

/// The helper-facing overlay decoded from `widget-snapshot.json`.
///
/// The file also carries widget-specific fields. `Codable` deliberately
/// ignores those unknown keys, allowing a Foundation-only process to read the
/// glance payload without linking WhereCore or RegionKit. Both properties are
/// optional so files published before this overlay existed still decode.
public struct WhereSurfaceDocument: Codable, Hashable, Sendable {
    public let generatedAt: Date?
    public let surface: WhereSurfaceSnapshot?

    public init(generatedAt: Date?, surface: WhereSurfaceSnapshot?) {
        self.generatedAt = generatedAt
        self.surface = surface
    }
}
