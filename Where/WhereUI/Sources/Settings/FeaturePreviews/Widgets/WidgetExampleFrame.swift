import SwiftUI

/// A rounded surface separating an actual widget from a miniature system screen.
struct WidgetExampleFrame<Content: View>: View {
    enum Surface {
        case homeScreen
        case lockScreen
    }

    let surface: Surface
    @ViewBuilder let content: Content

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        content
            .padding(stylesheet.featureDiscovery.widgets.frame.padding)
            .background(
                material,
                in: .rect(
                    cornerRadius: stylesheet.featureDiscovery.widgets.frame.cornerRadius,
                ),
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
        WidgetExampleFrame(surface: .homeScreen) {
            TodayWidgetView(snapshot: PreviewSupport.sampleWidgetSnapshot())
        }
        .aspectRatio(1, contentMode: .fit)
        .padding()
        .whereBroadwayRoot()
    }
#endif
