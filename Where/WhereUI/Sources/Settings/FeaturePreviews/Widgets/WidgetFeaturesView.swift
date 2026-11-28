import BroadwayUI
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// A visual catalog of every widget family Where currently offers, grouped on
/// the system surface where the user can add it.
struct WidgetFeaturesView: View {
    let focus: SettingsFocus?
    let presentation: FeatureDiscoveryPresentation

    var body: some View {
        StaggeredRevealScope {
            SettingsFocusScope(focus: focus) {
                WidgetFeaturesContent(presentation: presentation)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension WidgetFeaturesView: SettingsSection {
    static var destination: SettingsDestination {
        .widgets
    }

    enum Item: SettingsItem {
        case homeScreen
        case lockScreen

        var title: String {
            switch self {
                case .homeScreen: String(localized: .settingsExploreWidgetsHomeHeader)
                case .lockScreen: String(localized: .settingsExploreWidgetsLockHeader)
            }
        }

        var keywords: [String] {
            splitKeywords(String(localized: .settingsKeywordsWidgets))
        }
    }
}

#if DEBUG
    extension WidgetFeaturesView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentPhoneLightDarkWithAX5AndAnnotations + [
                    SnapshotConfiguration(contrast: .increased, device: .iPhoneFullContent),
                    SnapshotConfiguration(device: .iPadFullContent),
                    SnapshotConfiguration(device: .iPadFullContent, snapshotType: .accessibility),
                ],
                measurementReadiness: .immediate,
            ) {
                WidgetFeaturesView(
                    focus: nil,
                    presentation: PreviewSupport.featureDiscoveryPresentation(),
                )
            }
            whereSnapshot(
                name: "TwoRegions",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                WidgetFeaturesView(
                    focus: nil,
                    presentation: twoRegionPresentation,
                )
            }
        }

        private static var twoRegionPresentation: FeatureDiscoveryPresentation {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            let report = PreviewSupport.sampleReport()
            return FeatureDiscoveryPresentation(
                report: YearReport(
                    year: report.year,
                    days: report.days,
                    totals: [
                        .newYork: 121,
                        .california: 104,
                    ],
                ),
                selectedYear: report.year,
                referenceDate: PreviewSupport.referenceNow,
                calendar: calendar,
            )
        }
    }

    #Preview {
        NavigationStack {
            WidgetFeaturesView(
                focus: nil,
                presentation: PreviewSupport.featureDiscoveryPresentation(),
            )
        }
        .whereBroadwayRoot()
    }
#endif

#if DEBUG
    extension WidgetFeaturesView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            WidgetFeaturesView.self,
            title: "Widgets",
        )
    }
#endif

/// Keeps the gallery Form out of the enclosing focus and reveal scopes.
private struct WidgetFeaturesContent: View {
    let presentation: FeatureDiscoveryPresentation

    var body: some View {
        Form {
            FeatureMarketingHeaderRow(
                title: String(localized: .settingsExploreWidgetsTitle),
                tagline: .settingsExploreWidgetsTagline,
                destination: .widgets,
            )

            WidgetHomeScreenSection(presentation: presentation)

            WidgetLockScreenSection(presentation: presentation)
        }
        .whereFormRoot()
        .scrollContentBackground(.hidden)
        .background(FeatureDiscoveryBackground())
    }
}

private struct WidgetHomeScreenSection: View {
    let presentation: FeatureDiscoveryPresentation

    var body: some View {
        Section {
            FeatureHomeScreenExample(snapshot: presentation.widgetSnapshot)
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
                .settingsRow(WidgetFeaturesView.Item.homeScreen, restingBackground: .clear)
                .staggeredReveal(order: 1)
        } header: {
            Text(String(localized: .settingsExploreWidgetsHomeHeader))
                .staggeredReveal(order: 1)
        } footer: {
            Text(String(localized: .settingsExploreWidgetsHomeFooter))
                .staggeredReveal(order: 1)
        }
    }
}

#if DEBUG
    #Preview("Widget Features Content") {
        NavigationStack { WidgetFeaturesView.snapshotPreviews }
            .whereBroadwayRoot()
    }
#endif

/// A miniature Home Screen displaying every supported home-screen widget size.
private struct FeatureHomeScreenExample: View {
    let snapshot: WidgetSnapshot

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        VStack(spacing: style.widgets.device.spacing) {
            SmallHomeScreenWidgets(snapshot: snapshot)

            WidgetExampleFrame(surface: .homeScreen) {
                YearTotalsWidgetView(snapshot: snapshot, maxRows: 5)
            }
            .aspectRatio(2, contentMode: .fit)
        }
        .modifier(WidgetExampleDeviceFrame(surface: .homeScreen))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: .settingsExploreWidgetsHomePreviewLabel))
    }
}

private struct SmallHomeScreenWidgets: View {
    let snapshot: WidgetSnapshot

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
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
    }
}

#if DEBUG
    #Preview("Feature Home Screen Example") {
        FeatureHomeScreenExample(snapshot: PreviewSupport.sampleWidgetSnapshot())
            .padding()
            .whereBroadwayRoot()
    }
#endif
