import SwiftUI

/// An ordinary scrolling screen. Navigation, backgrounds, and presentation stay with callers.
struct WhereScreenRoot<Content: View>: View {
    private let width: WhereContentWidth?
    private let padding: WhereContentPadding
    private let content: Content

    @Environment(\.whereContentWidth) private var inheritedWidth
    @Environment(\.isInsideWhereContentRoot) private var isInsideRoot
    @Environment(\.whereContentRootDiagnostics) private var diagnostics
    @Environment(\.stylesheet.contentRoot) private var style

    init(
        _ width: WhereContentWidth? = nil,
        padding: WhereContentPadding = .standard,
        @ViewBuilder content: () -> Content,
    ) {
        self.width = width
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        if isInsideRoot {
            let _ = diagnostics.reportNesting()
            content
        } else {
            ContentRootScroll(
                padding: padding.insets(standard: style.standardPadding),
                width: width ?? inheritedWidth,
            ) { content }
        }
    }
}

private struct ContentRootScroll<Content: View>: View {
    let padding: EdgeInsets
    let width: WhereContentWidth
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            content
                .padding(padding)
                .whereContentRoot()
        }
        .environment(\.whereContentWidth, width)
    }
}

extension View {
    /// Adds vertical scrolling, padding, and one centered content root.
    /// Omitted width inherits the surrounding policy, whose default is regular.
    func whereScreenRoot(
        _ width: WhereContentWidth? = nil,
        padding: WhereContentPadding = .standard,
    ) -> some View {
        WhereScreenRoot(width, padding: padding) { self }
    }
}

#if DEBUG
    #Preview {
        Text("Screen content")
            .whereScreenRoot()
            .whereBroadwayRoot()
    }
#endif
