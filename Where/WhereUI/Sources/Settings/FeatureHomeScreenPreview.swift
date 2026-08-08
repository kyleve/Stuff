import SwiftUI
import WhereCore

/// A miniature Home Screen displaying every supported home-screen widget size.
struct FeatureHomeScreenPreview: View {
    let snapshot: WidgetSnapshot

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        VStack(spacing: style.deviceSpacing) {
            HStack(spacing: style.deviceSpacing) {
                WidgetPreviewFrame(surface: .homeScreen) {
                    TodayWidgetView(snapshot: snapshot)
                }
                .aspectRatio(1, contentMode: .fit)

                WidgetPreviewFrame(surface: .homeScreen) {
                    YearTotalsWidgetView(snapshot: snapshot)
                }
                .aspectRatio(1, contentMode: .fit)
            }

            WidgetPreviewFrame(surface: .homeScreen) {
                YearTotalsWidgetView(snapshot: snapshot, maxRows: 5)
            }
            .aspectRatio(2, contentMode: .fit)
        }
        .dynamicTypeSize(...style.widgetDynamicTypeLimit)
        .containerRelativeFrame(.horizontal) { length, _ in
            style.widgetContentWidth(in: length)
        }
        .padding(style.devicePadding)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [style.homeWallpaperTop, style.homeWallpaperBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            ),
            in: .rect(cornerRadius: style.deviceCornerRadius),
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: .settingsExploreWidgetsHomePreviewLabel))
    }
}

#if DEBUG
    #Preview {
        FeatureHomeScreenPreview(snapshot: PreviewSupport.sampleWidgetSnapshot())
            .padding()
            .whereBroadwayRoot()
    }
#endif
