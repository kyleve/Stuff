import SwiftUI

/// A rounded surface separating an actual widget from a miniature system screen.
struct WidgetExampleFrame<Content: View>: View {
    enum Surface: Equatable {
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
                surfaceStyle,
                in: .rect(
                    cornerRadius: stylesheet.featureDiscovery.widgets.frame.cornerRadius,
                ),
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: stylesheet.featureDiscovery.widgets.frame.cornerRadius,
                )
                .stroke(
                    stylesheet.palette.brand.brass.opacity(
                        surface == .homeScreen ? stylesheet.homeWidget.borderOpacity : 0,
                    ),
                    lineWidth: 0.75,
                )
            }
    }

    private var surfaceStyle: AnyShapeStyle {
        switch surface {
            case .homeScreen:
                AnyShapeStyle(stylesheet.palette.brand.raisedPaper)
            case .lockScreen:
                AnyShapeStyle(.ultraThinMaterial)
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
