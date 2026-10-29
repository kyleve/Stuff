import Foundation

/// Points, optionally scaled relative to a semantic font by the host.
public enum ViewDimension: Codable, Hashable, Sendable {
    case points(Double)
    case scaled(points: Double, relativeTo: ViewFontDescriptor.TextStyle)
}
