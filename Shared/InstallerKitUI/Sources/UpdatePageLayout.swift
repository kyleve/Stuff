import SwiftUI

/// Shared scrolling surface for the update page and its build browser.
struct UpdatePageLayout<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: stylesheet.page.spacing) {
                content
            }
            .frame(maxWidth: stylesheet.page.maximumWidth)
            .frame(maxWidth: .infinity)
            .padding(stylesheet.page.padding)
        }
        .background(stylesheet.page.background)
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif
