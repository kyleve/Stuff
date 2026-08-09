import SnapshotKit
import SwiftUI

/// A visual catalog of every user-facing App Intent Where ships to Siri and
/// Shortcuts, plus the tracked-region results it indexes into Spotlight.
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
                            SiriIntentFeature.allCases.enumerated(),
                            id: \.element,
                        ) { index, feature in
                            let personalized = presentation.siriExample(for: feature)
                            SiriIntentCard(
                                title: feature.item.title,
                                systemImage: feature.systemImage,
                                request: personalized?.request ?? feature.request,
                                response: personalized?.response ?? feature.response,
                            )
                            .listRowBackground(Color.clear)
                            .listRowInsets(.init(
                                top: style.siri.card.rowVerticalInset,
                                leading: 0,
                                bottom: style.siri.card.rowVerticalInset,
                                trailing: 0,
                            ))
                            .listRowSeparator(.hidden)
                            .settingsRow(feature.item, restingBackground: .clear)
                            .staggeredReveal(order: index + 1)
                        }
                    } footer: {
                        Text(String(localized: .settingsExploreSiriFooter))
                            .staggeredReveal(order: SiriIntentFeature.allCases.count + 1)
                    }

                    Section {
                        FeatureSpotlightPreview(example: presentation.spotlightExample)
                            .listRowBackground(Color.clear)
                            .listRowInsets(.init())
                            .settingsRow(Item.spotlight, restingBackground: .clear)
                            .staggeredReveal(order: SiriIntentFeature.allCases.count + 1)
                    } footer: {
                        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                            Text(String(localized: .settingsExploreSpotlightFooter))
                            FeatureDiscoveryDataFooter()
                        }
                        .staggeredReveal(order: SiriIntentFeature.allCases.count + 2)
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
        case spotlight

        var title: String {
            switch self {
                case .todayRegions: String(localized: .settingsExploreSiriTodayTitle)
                case .daysInRegion: String(localized: .settingsExploreSiriDaysTitle)
                case .regionOnDate: String(localized: .settingsExploreSiriDateTitle)
                case .recentActivity: String(localized: .settingsExploreSiriRecentTitle)
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
            title: "Siri, Shortcuts & Spotlight",
        )
    }
#endif
