import BroadwayUI
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

struct WidgetLockScreenSection: View {
    let presentation: FeatureDiscoveryPresentation

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Section {
            FeatureLockScreenExample(
                date: presentation.lockScreenDate,
                snapshot: presentation.widgetSnapshot,
            )
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
            .settingsRow(WidgetFeaturesView.Item.lockScreen, restingBackground: .clear)
            .staggeredReveal(order: 2)
        } header: {
            Text(String(localized: .settingsExploreWidgetsLockHeader))
                .staggeredReveal(order: 2)
        } footer: {
            VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                Text(String(localized: .settingsExploreWidgetsLockFooter))
                    .staggeredReveal(order: 2)
                FeatureDiscoveryDataFooter()
                    .staggeredReveal(order: 3)
            }
        }
    }
}

#if DEBUG
    #Preview { NavigationStack { WidgetFeaturesView.snapshotPreviews }.whereBroadwayRoot() }
#endif

/// A miniature Lock Screen displaying every supported accessory widget family.
private struct FeatureLockScreenExample: View {
    let date: Date
    let snapshot: WidgetSnapshot

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        VStack(spacing: style.widgets.device.spacing) {
            LockScreenClock(date: date)

            WidgetExampleFrame(surface: .lockScreen) {
                TodayInlineAccessoryView(snapshot: snapshot)
                    .font(.caption)
            }

            LockScreenAccessoryWidgets(snapshot: snapshot)
        }
        .foregroundStyle(.white)
        .modifier(WidgetExampleDeviceFrame(surface: .lockScreen))
        .environment(\.colorScheme, .dark)
        .bMode(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: .settingsExploreWidgetsLockPreviewLabel))
    }
}

private struct LockScreenAccessoryWidgets: View {
    let snapshot: WidgetSnapshot

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
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
}

private struct LockScreenClock: View {
    let date: Date

    var body: some View {
        Text(date, format: .dateTime.weekday(.wide).month(.wide).day())
            .font(.subheadline)
        Text(date, format: .dateTime.hour().minute())
            .font(.largeTitle)
            .bold()
    }
}

#if DEBUG
    #Preview("Feature Lock Screen Example") {
        FeatureLockScreenExample(
            date: PreviewSupport.referenceNow,
            snapshot: PreviewSupport.sampleWidgetSnapshot(),
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
