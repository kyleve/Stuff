import BroadwayCore
import BroadwayUI
import SwiftUI

/// Preview selection affects the ready app while launch and onboarding keep the saved built-in.
struct WhereReadyTheme: ViewModifier {
    @Environment(\.whereThemePreview) private var preview
    @Environment(\.bContext) private var context
    @Environment(\.whereThemeDocument) private var inheritedDocument

    private var themedContext: BContext {
        guard let theme = preview?.theme else { return context }
        var context = context
        context.themes[WhereDocumentTheme.self] = .init(document: theme.validated)
        return context
    }

    func body(content: Content) -> some View {
        content
            .environment(\.bContext, themedContext)
            .environment(\.whereThemeDocument, preview?.theme ?? inheritedDocument)
    }
}
