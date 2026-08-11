import SwiftUI
import WidgetKit

extension View {
    /// Applies Where's active paper or midnight document stock as a WidgetKit
    /// container without exposing Broadway to the widget extension.
    public func whereWidgetBackground() -> some View {
        modifier(WhereWidgetBackgroundModifier())
    }
}

private struct WhereWidgetBackgroundModifier: ViewModifier {
    @Environment(\.stylesheet) private var stylesheet

    func body(content: Content) -> some View {
        let brand = stylesheet.palette.brand
        let style = stylesheet.homeWidget
        content
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [brand.raisedPaper, brand.canvas],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                )
                .overlay {
                    ContainerRelativeShape()
                        .stroke(
                            brand.brass.opacity(style.borderOpacity),
                            lineWidth: 0.75,
                        )
                }
            }
    }
}
