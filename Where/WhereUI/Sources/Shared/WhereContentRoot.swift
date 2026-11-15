import SwiftUI

extension View {
    /// Centers this content within the inherited width limit. Apply after padding,
    /// inside the scroll view, so scrolling and native chrome retain their full width.
    /// Nested roots assert in debug builds and pass through in release builds.
    func whereContentRoot() -> some View {
        modifier(WhereContentRootModifier())
    }
}

extension EnvironmentValues {
    @Entry fileprivate var isInsideWhereContentRoot = false
}

private struct WhereContentRootModifier: ViewModifier {
    @Environment(\.whereContentWidth) private var width
    @Environment(\.isInsideWhereContentRoot) private var isInsideRoot
    @Environment(\.stylesheet.contentRoot) private var style

    func body(content: Content) -> some View {
        let _ = assert(
            !isInsideRoot,
            "Do not nest whereContentRoot(). Apply it once to the scrolling content, after padding.",
        )
        if isInsideRoot {
            content
        } else {
            content
                .frame(minWidth: 0, maxWidth: style.maximumWidth(for: width))
                .frame(maxWidth: .infinity)
                .environment(\.isInsideWhereContentRoot, true)
        }
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
