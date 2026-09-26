import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// A visual catalog of every user-facing App Intent Where ships to Siri and
/// Shortcuts, plus the tracked-region results it indexes into Spotlight.
struct SiriFeaturesView: View {
    let focus: SettingsFocus?
    let presentation: FeatureDiscoveryPresentation

    var body: some View {
        StaggeredRevealScope {
            SettingsFocusScope(focus: focus) {
                SiriFeaturesContent(presentation: presentation)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension SiriFeaturesView: SettingsSection {
    static var destination: SettingsDestination {
        .siri
    }

    enum Item: SettingsItem {
        case todayRegions
        case daysInRegion
        case regionOnDate
        case logDay
        case logTrip
        case spotlight

        var title: String {
            switch self {
                case .todayRegions: String(localized: .settingsExploreSiriTodayTitle)
                case .daysInRegion: String(localized: .settingsExploreSiriDaysTitle)
                case .regionOnDate: String(localized: .settingsExploreSiriDateTitle)
                case .logDay: String(localized: .settingsExploreSiriLogDayTitle)
                case .logTrip: String(localized: .settingsExploreSiriLogTripTitle)
                case .spotlight: String(localized: .settingsExploreSpotlightTitle)
            }
        }

        var keywords: [String] {
            splitKeywords(String(localized: .settingsKeywordsSiri))
        }
    }
}

#if DEBUG
    extension SiriFeaturesView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentScreenDefaults,
                measurementReadiness: .immediate,
            ) {
                SiriFeaturesView(
                    focus: nil,
                    presentation: PreviewSupport.featureDiscoveryPresentation(),
                )
            }
        }
    }

    #Preview {
        NavigationStack {
            SiriFeaturesView(
                focus: nil,
                presentation: PreviewSupport.featureDiscoveryPresentation(),
            )
        }
        .whereBroadwayRoot()
    }
#endif

#if DEBUG
    extension SiriFeaturesView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            SiriFeaturesView.self,
            title: "Siri, Shortcuts & Spotlight",
        )
    }
#endif
