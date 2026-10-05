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
                configurations: .fullContentScreenDefaults,
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
