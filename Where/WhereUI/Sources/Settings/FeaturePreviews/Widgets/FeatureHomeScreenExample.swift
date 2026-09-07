import SwiftUI
import WhereCore

/// A miniature Home Screen displaying every supported home-screen widget size.
struct FeatureHomeScreenExample: View {
    let snapshot: WidgetSnapshot

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        VStack(spacing: style.widgets.device.spacing) {
            HStack(spacing: style.widgets.device.spacing) {
                WidgetExampleFrame(surface: .homeScreen) {
                    TodayWidgetView(snapshot: snapshot)
                }
                .aspectRatio(1, contentMode: .fit)

                WidgetExampleFrame(surface: .homeScreen) {
                    YearTotalsWidgetView(snapshot: snapshot)
                }
                .aspectRatio(1, contentMode: .fit)
            }

            WidgetExampleFrame(surface: .homeScreen) {
                YearTotalsWidgetView(snapshot: snapshot, maxRows: 5)
            }
            .aspectRatio(2, contentMode: .fit)
        }
        .dynamicTypeSize(...style.widgets.device.dynamicTypeLimit)
        .containerRelativeFrame(.horizontal) { length, _ in
            style.widgets.contentWidth(in: length)
        }
        .padding(style.widgets.device.padding)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [style.widgets.wallpapers.home.top, style.widgets.wallpapers.home.bottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            ),
            in: .rect(cornerRadius: style.widgets.device.cornerRadius),
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: .settingsExploreWidgetsHomePreviewLabel))
    }
}

#if DEBUG
    #Preview {
        FeatureHomeScreenExample(snapshot: PreviewSupport.sampleWidgetSnapshot())
            .padding()
            .whereBroadwayRoot()
    }
#endif
