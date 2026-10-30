import SwiftUI

/// Keeps supporting native text readable when a document supplies the surrounding ink.
struct WhereSecondaryContentStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        if let ink = environment.whereThemeSecondaryInk {
            AnyShapeStyle(ink)
        } else {
            AnyShapeStyle(.secondary)
        }
    }
}

extension ShapeStyle where Self == WhereSecondaryContentStyle {
    static var whereSecondary: Self {
        .init()
    }
}
