import SnapshotKit
import SwiftUI

/// A visual catalog of every user-facing App Intent Where ships to Siri and
/// Shortcuts. The dialogue uses the selected report once it has enough history;
/// browsing the catalog never changes user data.
struct SiriFeaturesView: View {
    let focus: SettingsFocus?
    let presentation: FeatureDiscoveryPresentation

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        StaggeredRevealScope {
            SettingsFocusScope(focus: focus) {
                Form {
                    FeatureMarketingHeader(
                        title: String(localized: .settingsExploreSiriTitle),
                        tagline: String(localized: .settingsExploreSiriTagline),
                        systemImage: SettingsDestination.siri.systemImage,
                        tint: SettingsDestination.siri.iconColor,
                    )
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .staggeredReveal(order: 0)

                    Section {
                        ForEach(
                            Array(Item.allCases.enumerated()),
                            id: \.element,
                        ) { index, feature in
                            let personalized = presentation.siriExample(for: feature)
                            SiriIntentCard(
                                title: feature.title,
                                systemImage: feature.systemImage,
                                request: personalized?.request ?? feature.request,
                                response: personalized?.response ?? feature.response,
                            )
                            .listRowBackground(Color.clear)
                            .listRowInsets(.init(
                                top: style.cardRowVerticalInset,
                                leading: 0,
                                bottom: style.cardRowVerticalInset,
                                trailing: 0,
                            ))
                            .listRowSeparator(.hidden)
                            .settingsRow(feature, restingBackground: .clear)
                            .staggeredReveal(order: index + 1)
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                            Text(String(localized: .settingsExploreSiriFooter))
                            Text(String(localized: .settingsExploreSiriDataFooter))
                        }
                        .staggeredReveal(order: Item.allCases.count + 1)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(FeatureDiscoveryBackground())
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
            title: "Siri & Shortcuts",
        )
    }
#endif
