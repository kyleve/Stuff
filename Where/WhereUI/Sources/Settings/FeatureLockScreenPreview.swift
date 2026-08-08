import SwiftUI
import WhereCore

/// A miniature Lock Screen displaying every supported accessory widget family.
struct FeatureLockScreenPreview: View {
    let date: Date
    let snapshot: WidgetSnapshot

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
        .padding(style.devicePadding)
        .frame(maxWidth: deviceMaxWidth)
        .background(
            LinearGradient(
                colors: [style.lockWallpaperTop, style.lockWallpaperBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            ),
            in: .rect(cornerRadius: style.deviceCornerRadius),
        )
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: .settingsExploreWidgetsLockPreviewLabel))
    }

    private var deviceMaxWidth: CGFloat {
        horizontalSizeClass == .regular
            ? stylesheet.featureDiscovery.regularDeviceMaxWidth
            : stylesheet.featureDiscovery.deviceMaxWidth
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
