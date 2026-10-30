import SwiftUI

/// Reserves paint outside the interactive or accessible child. Apply after button styling
/// and accessibility grouping, never inside a button label.
private struct WhereThemeArtworkSpace: ViewModifier {
    let role: WhereThemeComponents.Role
    @Environment(\.whereComponentStylesheet) private var stylesheet

    func body(content: Content) -> some View {
        content.padding(stylesheet[role].outsets)
    }
}

extension View {
    func whereThemeArtworkSpace(_ role: WhereThemeComponents.Role) -> some View {
        modifier(WhereThemeArtworkSpace(role: role))
    }
}
