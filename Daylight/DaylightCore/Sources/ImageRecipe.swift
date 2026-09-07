import Foundation

/// Versioned photographic adjustments stored with each Photos asset.
public struct ImageRecipe: Codable, Equatable, Sendable {
    public enum Preset: String, CaseIterable, Codable,
        Sendable { case original, warm, vivid, monochrome }
    public var version = 1
    public var preset: Preset = .original
    public var strength = 1.0
    public var exposure = 0.0
    public var contrast = 1.0
    public var highlights = 1.0
    public var shadows = 0.0
    public var saturation = 1.0
    public var warmth = 0.0
    public static let original = Self()

    public func validate() throws {
        guard version == 1 else { throw DaylightError.unsupportedVersion }
        guard (0 ... 1).contains(strength), (-2 ... 2).contains(exposure),
              (0.5 ... 1.5).contains(contrast),
              (0 ... 1).contains(highlights), (0 ... 1).contains(shadows),
              (0 ... 2).contains(saturation),
              (-1 ... 1).contains(warmth) else { throw DaylightError.invalidSettings }
    }
}
