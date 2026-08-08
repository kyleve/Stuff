import SwiftUI
import WhereCore

/// A miniature Lock Screen displaying every supported accessory widget family.
struct FeatureLockScreenPreview: View {
    let date: Date
    let snapshot: WidgetSnapshot

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        VStack(spacing: style.deviceSpacing) {
            Text(date, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline)
            Text(date, format: .dateTime.hour().minute())
                .font(.largeTitle)
                .bold()

            WidgetPreviewFrame(surface: .lockScreen) {
                TodayInlineAccessoryView(snapshot: snapshot)
                    .font(.caption)
            }

            HStack(spacing: style.deviceSpacing) {
                WidgetPreviewFrame(surface: .lockScreen) {
                    TodayCircularAccessoryView(snapshot: snapshot)
                }
                .aspectRatio(1, contentMode: .fit)

                WidgetPreviewFrame(surface: .lockScreen) {
                    YearTotalsRectangularAccessoryView(snapshot: snapshot)
                }
                .aspectRatio(2, contentMode: .fit)
            }
        }
        .foregroundStyle(.white)
        .dynamicTypeSize(...style.widgetDynamicTypeLimit)
        .containerRelativeFrame(.horizontal) { length, _ in
            style.widgetContentWidth(in: length)
        }
        .padding(style.devicePadding)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [style.lockWallpaperTop, style.lockWallpaperBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            ),
            in: .rect(cornerRadius: style.deviceCornerRadius),
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: .settingsExploreWidgetsLockPreviewLabel))
    }
}

#if DEBUG
    #Preview {
        FeatureLockScreenPreview(
            date: PreviewSupport.referenceNow,
            snapshot: PreviewSupport.sampleWidgetSnapshot(),
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
