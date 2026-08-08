import SwiftUI
import WhereCore

/// A miniature Home Screen displaying every supported home-screen widget size.
struct FeatureHomeScreenPreview: View {
    let snapshot: WidgetSnapshot

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        VStack(spacing: style.deviceSpacing) {
            AnyLayout(
                style.stacksHomeWidgets
                    ? AnyLayout(VStackLayout(spacing: style.deviceSpacing))
                    : AnyLayout(HStackLayout(spacing: style.deviceSpacing)),
            ) {
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
        .padding(style.devicePadding)
        .frame(maxWidth: deviceMaxWidth)
        .background(
            LinearGradient(
                colors: [style.homeWallpaperTop, style.homeWallpaperBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            ),
            in: .rect(cornerRadius: style.deviceCornerRadius),
        )
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: .settingsExploreWidgetsHomePreviewLabel))
    }

    private var deviceMaxWidth: CGFloat {
        horizontalSizeClass == .regular
            ? stylesheet.featureDiscovery.regularDeviceMaxWidth
            : stylesheet.featureDiscovery.deviceMaxWidth
    }
}

#if DEBUG
    #Preview {
        FeatureHomeScreenPreview(snapshot: PreviewSupport.sampleWidgetSnapshot())
            .padding()
            .whereBroadwayRoot()
    }
#endif
