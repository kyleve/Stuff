import SwiftUI
import WhereCore

/// A miniature Lock Screen displaying every supported accessory widget family.
struct FeatureLockScreenPreview: View {
    let snapshot: WidgetSnapshot

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        VStack(spacing: style.deviceSpacing) {
            Text(snapshot.day, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline)
            Text(snapshot.day, format: .dateTime.hour().minute())
                .font(.largeTitle)
                .bold()

            TodayInlineAccessoryView(snapshot: snapshot)
                .font(.caption)

            HStack(spacing: style.deviceSpacing) {
                TodayCircularAccessoryView(snapshot: snapshot)
                    .aspectRatio(1, contentMode: .fit)
                YearTotalsRectangularAccessoryView(snapshot: snapshot)
                    .padding(style.widgetPadding)
                    .background(
                        .ultraThinMaterial,
                        in: .rect(cornerRadius: style.widgetCornerRadius),
                    )
                    .aspectRatio(2, contentMode: .fit)
            }
        }
        .foregroundStyle(.white)
        .padding(style.devicePadding)
        .frame(maxWidth: style.deviceMaxWidth)
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
}

#if DEBUG
    #Preview {
        FeatureLockScreenPreview(snapshot: PreviewSupport.sampleWidgetSnapshot())
            .padding()
            .whereBroadwayRoot()
    }
#endif
