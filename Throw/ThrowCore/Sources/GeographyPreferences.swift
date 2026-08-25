import Foundation

public struct GeographyPreferences: Equatable, Sendable {
    public static let allowedIntensityPercent = 0.0 ... 20.0
    public static let defaultValue = try! GeographyPreferences(
        isEnabled: true,
        intensityPercent: 8,
    )

    public let isEnabled: Bool
    public let intensityPercent: Double

    public init(isEnabled: Bool, intensityPercent: Double) throws {
        guard intensityPercent.isFinite else {
            throw ThrowValidationError.nonFiniteValue(field: "geographyIntensity")
        }
        guard Self.allowedIntensityPercent.contains(intensityPercent) else {
            throw ThrowValidationError.outOfRange(
                field: "geographyIntensity",
                closedRange: Self.allowedIntensityPercent,
            )
        }
        self.isEnabled = isEnabled
        self.intensityPercent = intensityPercent
    }
}
