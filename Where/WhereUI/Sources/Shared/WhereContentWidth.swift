import SwiftUI

/// The inherited width policy for content that uses `whereContentRoot()`.
enum WhereContentWidth: CaseIterable, Hashable {
    case regular
    case wide
    case fluid
}

extension EnvironmentValues {
    @Entry var whereContentWidth = WhereContentWidth.regular
}

extension View {
    /// Selects the width of descendant content roots without sizing this view.
    func whereContentWidth(_ width: WhereContentWidth) -> some View {
        environment(\.whereContentWidth, width)
    }
}
