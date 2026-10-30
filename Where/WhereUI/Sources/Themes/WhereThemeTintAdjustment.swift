import BroadwayCore
import ViewDocumentCore
import ViewDocumentUI

public struct WhereThemeTintAdjustment: Codable, Hashable, Sendable {
    public var color: BThemeValue<ViewColorDescriptor>?
    public var fraction: Double?
    public init() {}
    public init(color: BThemeValue<ViewColorDescriptor>?, fraction: Double?) {
        self.color = color
        self.fraction = fraction
    }

    func resolve(
        mode: BMode,
        appearance: ViewDocumentAppearance,
        base: WhereStylesheet.TintAdjustment,
    ) throws -> WhereStylesheet.TintAdjustment {
        var result = base
        if let color = color?.resolve(mode: mode) {
            try WhereThemeValidation.validate(color, path: "tint.color")
            result.color = appearance.color(color)
        }
        if let fraction {
            try WhereThemeValidation.validate(fraction, path: "tint.fraction")
            result.fraction = fraction
        }
        return result
    }
}
