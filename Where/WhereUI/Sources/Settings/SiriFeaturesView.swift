import SnapshotKit
import SwiftUI

/// A visual catalog of every user-facing App Intent Where ships to Siri and
/// Shortcuts. The dialogue is illustrative and never reads or changes user data.
struct SiriFeaturesView: View {
    let focus: SettingsFocus?

    var body: some View {
        SettingsFocusScope(focus: focus) {
            Form {
                Section {
                    Text(String(localized: .settingsExploreSiriIntroduction))
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(Item.allCases, id: \.self) { feature in
                        SiriIntentCard(
                            title: feature.title,
                            systemImage: feature.systemImage,
                            request: feature.request,
                            response: feature.response,
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                        .settingsRow(feature)
                    }
                } footer: {
                    Text(String(localized: .settingsExploreSiriFooter))
                }
            }
        }
        .navigationTitle(String(localized: .settingsExploreSiriTitle))
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
        case recentActivity
        case logDay
        case logTrip

        var title: String {
            switch self {
                case .todayRegions: String(localized: .settingsExploreSiriTodayTitle)
                case .daysInRegion: String(localized: .settingsExploreSiriDaysTitle)
                case .regionOnDate: String(localized: .settingsExploreSiriDateTitle)
                case .recentActivity: String(localized: .settingsExploreSiriRecentTitle)
                case .logDay: String(localized: .settingsExploreSiriLogDayTitle)
                case .logTrip: String(localized: .settingsExploreSiriLogTripTitle)
            }
        }

        var keywords: [String] {
            splitKeywords(String(localized: .settingsKeywordsSiri))
        }

        var systemImage: String {
            switch self {
                case .todayRegions: "location.fill"
                case .daysInRegion: "calendar"
                case .regionOnDate: "calendar.badge.clock"
                case .recentActivity: "sparkles"
                case .logDay: "mappin.and.ellipse"
                case .logTrip: "airplane"
            }
        }

        var request: String {
            switch self {
                case .todayRegions: String(localized: .settingsExploreSiriTodayRequest)
                case .daysInRegion: String(localized: .settingsExploreSiriDaysRequest)
                case .regionOnDate: String(localized: .settingsExploreSiriDateRequest)
                case .recentActivity: String(localized: .settingsExploreSiriRecentRequest)
                case .logDay: String(localized: .settingsExploreSiriLogDayRequest)
                case .logTrip: String(localized: .settingsExploreSiriLogTripRequest)
            }
        }

        var response: String {
            switch self {
                case .todayRegions: String(localized: .settingsExploreSiriTodayResponse)
                case .daysInRegion: String(localized: .settingsExploreSiriDaysResponse)
                case .regionOnDate: String(localized: .settingsExploreSiriDateResponse)
                case .recentActivity: String(localized: .settingsExploreSiriRecentResponse)
                case .logDay: String(localized: .settingsExploreSiriLogDayResponse)
                case .logTrip: String(localized: .settingsExploreSiriLogTripResponse)
            }
        }
    }
}

#if DEBUG
    extension SiriFeaturesView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .fullContentScreenDefaults) {
                SiriFeaturesView(focus: nil)
            }
        }
    }

    #Preview {
        NavigationStack {
            SiriFeaturesView(focus: nil)
        }
        .whereBroadwayRoot()
    }
#endif

#if DEBUG
    extension SiriFeaturesView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            SiriFeaturesView.self,
            title: "Siri & Shortcuts",
        )
    }
#endif
