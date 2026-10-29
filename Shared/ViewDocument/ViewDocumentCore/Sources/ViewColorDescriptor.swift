import Foundation

/// Portable colors. Explicit components use the sRGB color space.
public enum ViewColorDescriptor: Codable, Hashable, Sendable {
    case rgba(red: Double, green: Double, blue: Double, alpha: Double)
    case semantic(Role)

    public enum Role: String, Codable, Hashable, Sendable {
        case primary, secondary, accent, background
    }
}
