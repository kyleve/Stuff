import Foundation

/// Portable colors. Explicit components use the sRGB color space.
public indirect enum ViewColorDescriptor: Codable, Hashable, Sendable {
    case rgba(red: Double, green: Double, blue: Double, alpha: Double)
    case semantic(Role)
    case opacity(ViewColorDescriptor, Double)
    /// A bounded perceptual blend of two portable colors.
    case mix(ViewColorDescriptor, ViewColorDescriptor, fraction: Double)

    public enum Role: String, Codable, Hashable, Sendable {
        case primary, secondary, accent, background
        case secondaryBackground, groupedBackground, secondaryGroupedBackground
        /// Native palette colors retain appearance and accessibility adaptation.
        case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray
        case black, white, clear
    }
}
