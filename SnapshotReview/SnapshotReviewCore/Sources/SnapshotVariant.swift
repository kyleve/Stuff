import Foundation

/// Device-independent appearance axes, used to pair equivalent images across frames.
public struct SnapshotVariant: Codable, Hashable, Sendable {
    public enum Appearance: String, Codable, CaseIterable, Sendable {
        case light
        case dark
        case other
    }

    public enum ColorScheme: String, Codable, Sendable {
        case light
        case dark
    }

    public var colorScheme: ColorScheme
    public var dynamicType: String
    public var increasedContrast: Bool
    public var rightToLeft: Bool
    public var bold: Bool
    public var accessibility: Bool

    public init(
        colorScheme: ColorScheme,
        dynamicType: String,
        increasedContrast: Bool,
        rightToLeft: Bool,
        bold: Bool,
        accessibility: Bool,
    ) {
        self.colorScheme = colorScheme
        self.dynamicType = dynamicType
        self.increasedContrast = increasedContrast
        self.rightToLeft = rightToLeft
        self.bold = bold
        self.accessibility = accessibility
    }

    public static let light = Self(
        colorScheme: .light,
        dynamicType: "large",
        increasedContrast: false,
        rightToLeft: false,
        bold: false,
        accessibility: false,
    )
    public static let dark = Self(
        colorScheme: .dark,
        dynamicType: "large",
        increasedContrast: false,
        rightToLeft: false,
        bold: false,
        accessibility: false,
    )

    public var appearance: Appearance {
        if dynamicType != "large" || increasedContrast || rightToLeft || bold ||
            accessibility { return .other }
        return colorScheme == .light ? .light : .dark
    }

    public var label: String {
        var parts = [colorScheme == .light ? "Light" : "Dark"]
        if dynamicType != "large" { parts.append(dynamicType) }
        if increasedContrast { parts.append("Increased contrast") }
        if rightToLeft { parts.append("Right to left") }
        if bold { parts.append("Bold") }
        if accessibility { parts.append("VoiceOver") }
        return parts.joined(separator: " · ")
    }
}
