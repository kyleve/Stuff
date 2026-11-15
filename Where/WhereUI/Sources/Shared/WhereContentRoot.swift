import SwiftUI

extension View {
    /// Centers this content within the inherited width limit. Apply after padding,
    /// inside the scroll view, so scrolling and native chrome retain their full width.
    func whereContentRoot() -> some View {
        modifier(WhereContentRootModifier())
    }
}

private struct WhereContentRootModifier: ViewModifier {
    @Environment(\.whereContentWidth) private var width
    @Environment(\.stylesheet.contentRoot) private var style

    func body(content: Content) -> some View {
        content
            .frame(minWidth: 0, maxWidth: style.maximumWidth(for: width))
            .frame(maxWidth: .infinity)
    }
}

#if DEBUG
    #Preview {
        ScrollView {
            Color.accentColor
                .frame(height: 160)
                .padding()
                .whereContentRoot()
        }
        .whereBroadwayRoot()
    }
#endif
