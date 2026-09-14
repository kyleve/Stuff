import SwiftUI

/// Reuses the developer launcher inside native application modals. Presentation remains
/// owned by the application's single window anchor.
struct WherePortholeModalTools: ViewModifier {
    @Environment(WhereModel.self) private var model: WhereModel?
    @State private var overlayInsets = EdgeInsets()

    func body(content: Content) -> some View {
        content.safeAreaPadding(overlayInsets)
            .overlay {
                if model != nil {
                    #if DEBUG
                        DeveloperOverlay(tabBarInset: 0)
                    #else
                        if model?.porthole.isEnabled == true { DeveloperOverlay(tabBarInset: 0) }
                    #endif
                }
            }
            .onPreferenceChange(DeveloperOverlayInsetKey.self) { overlayInsets = $0 }
    }
}

#if DEBUG
    #Preview {
        NavigationStack { Text("Selected application issue") }
            .modifier(WherePortholeModalTools())
            .environment(PreviewSupport.loadedModel())
            .whereBroadwayRoot()
    }
#endif
