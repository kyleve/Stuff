import SwiftUI
import WhereCore

/// A miniature Lock Screen displaying every supported accessory widget family.
struct FeatureLockScreenExample: View {
    let date: Date
    let snapshot: WidgetSnapshot

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        VStack(spacing: style.widgets.device.spacing) {
            Text(date, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline)
            Text(date, format: .dateTime.hour().minute())
                .font(.largeTitle)
                .bold()

            WidgetExampleFrame(surface: .lockScreen) {
                TodayInlineAccessoryView(snapshot: snapshot)
                    .font(.caption)
            }

            HStack(spacing: style.widgets.device.spacing) {
                WidgetExampleFrame(surface: .lockScreen) {
                    TodayCircularAccessoryView(snapshot: snapshot)
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(height: style.widgets.lockWidgetHeight)

                WidgetExampleFrame(surface: .lockScreen) {
                    YearTotalsRectangularAccessoryView(snapshot: snapshot)
                }
                .aspectRatio(2, contentMode: .fit)
                .frame(height: style.widgets.lockWidgetHeight)
            }
        }
        .foregroundStyle(.white)
        .dynamicTypeSize(...style.widgets.device.dynamicTypeLimit)
        .containerRelativeFrame(.horizontal) { length, _ in
            style.widgets.contentWidth(in: length)
        }
        .padding(style.widgets.device.padding)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [style.widgets.wallpapers.lock.top, style.widgets.wallpapers.lock.bottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            ),
            in: .rect(cornerRadius: style.widgets.device.cornerRadius),
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: .settingsExploreWidgetsLockPreviewLabel))
    }
}

#if DEBUG
    #Preview {
        FeatureLockScreenExample(
            date: PreviewSupport.referenceNow,
            snapshot: PreviewSupport.sampleWidgetSnapshot(),
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
