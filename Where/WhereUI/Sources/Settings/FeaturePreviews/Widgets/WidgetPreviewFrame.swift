import SwiftUI

/// A rounded surface separating an actual widget from a miniature system screen.
struct WidgetPreviewFrame<Content: View>: View {
    enum Surface {
        case homeScreen
        case lockScreen
    }

    let surface: Surface
    @ViewBuilder let content: Content

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        content
            .padding(stylesheet.featureDiscovery.widgetPadding)
            .background(
                material,
                in: .rect(cornerRadius: stylesheet.featureDiscovery.widgetCornerRadius),
            )
    }

    private var material: Material {
        switch surface {
            case .homeScreen:
                .regularMaterial
            case .lockScreen:
                .ultraThinMaterial
        }
    }
}

#if DEBUG
    #Preview {
        WidgetPreviewFrame(surface: .homeScreen) {
            TodayWidgetView(snapshot: PreviewSupport.sampleWidgetSnapshot())
        }
        .aspectRatio(1, contentMode: .fit)
        .padding()
        .whereBroadwayRoot()
    }
#endif
