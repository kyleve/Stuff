import SwiftUI
import WhereCore

/// A miniature Home Screen displaying every supported home-screen widget size.
struct FeatureHomeScreenPreview: View {
    let snapshot: WidgetSnapshot

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        VStack(spacing: style.deviceSpacing) {
            AnyLayout(
                style.stacksHomeWidgets
                    ? AnyLayout(VStackLayout(spacing: style.deviceSpacing))
                    : AnyLayout(HStackLayout(spacing: style.deviceSpacing)),
            ) {
                HomeScreenWidgetFrame {
                    TodayWidgetView(snapshot: snapshot)
                }
                .aspectRatio(1, contentMode: .fit)

                HomeScreenWidgetFrame {
                    YearTotalsWidgetView(snapshot: snapshot)
                }
                .aspectRatio(1, contentMode: .fit)
            }

            HomeScreenWidgetFrame {
                YearTotalsWidgetView(snapshot: snapshot, maxRows: 5)
            }
            .aspectRatio(2, contentMode: .fit)
        }
        .padding(style.devicePadding)
        .frame(maxWidth: style.deviceMaxWidth)
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
}

#if DEBUG
    #Preview {
        FeatureHomeScreenPreview(snapshot: PreviewSupport.sampleWidgetSnapshot())
            .padding()
            .whereBroadwayRoot()
    }
#endif
