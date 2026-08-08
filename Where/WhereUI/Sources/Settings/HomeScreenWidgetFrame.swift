import SwiftUI

/// The rounded surface around an actual widget view in the miniature Home Screen.
struct HomeScreenWidgetFrame<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        content
            .padding(stylesheet.featureDiscovery.widgetPadding)
            .background(
                .regularMaterial,
                in: .rect(cornerRadius: stylesheet.featureDiscovery.widgetCornerRadius),
            )
    }
}

#if DEBUG
    #Preview {
        HomeScreenWidgetFrame {
            TodayWidgetView(snapshot: PreviewSupport.sampleWidgetSnapshot())
        }
        .aspectRatio(1, contentMode: .fit)
        .padding()
        .whereBroadwayRoot()
    }
#endif
