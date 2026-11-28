import SwiftUI

extension View {
    /// Centers native Form/List content while retaining its scroller and section styling.
    /// Apply to the native container, before navigation or sheet presentation modifiers.
    func whereFormRoot(_ width: WhereContentWidth? = nil) -> some View {
        modifier(WhereFormRootModifier(width: width))
    }
}

private struct WhereFormRootModifier: ViewModifier {
    let width: WhereContentWidth?
    @State private var availableWidth: CGFloat = 0
    @Environment(\.whereContentWidth) private var inheritedWidth
    @Environment(\.stylesheet.contentRoot) private var style
    @Environment(\.isInsideWhereContentRoot) private var isInsideRoot
    @Environment(\.whereContentRootDiagnostics) private var diagnostics

    func body(content: Content) -> some View {
        if isInsideRoot {
            let _ = diagnostics.reportNesting()
            content
        } else {
            let limit = style.maximumWidth(for: width ?? inheritedWidth)
            let gutter = max(0, (availableWidth - limit) / 2)
            content
                // Add to the native gutters instead of replacing style-specific margins.
                // Compensate indicators for only this added safe area, preserving caller insets.
                .contentMargins(.horizontal, gutter > 0 ? -gutter : nil, for: .scrollIndicators)
                .safeAreaPadding(.horizontal, gutter)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    // The proposal already excludes the caller's safe-area padding.
                    geometry.size.width
                } action: { availableWidth = $0 }
                .environment(\.whereContentWidth, width ?? inheritedWidth)
                .environment(\.isInsideWhereContentRoot, true)
        }
    }
}

#if DEBUG
    #Preview { NativeFormExample() }

    private struct NativeFormExample: View {
        var body: some View {
            Form {
                Section("Settings") {
                    Text("Native row")
                }
            }
            .whereFormRoot()
            .whereBroadwayRoot()
        }
    }
#endif
