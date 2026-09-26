import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// A read-only walkthrough of your places & your year with explicit actions into existing screens.
struct PlacesYearFeaturesView: View {
    let report: YearReportModel
    let focus: SettingsFocus?

    var body: some View {
        FeatureGuidePage(
            destination: .placesYear,
            tagline: .settingsExplorePlacesTagline,
            focus: focus,
        ) {
            FeatureGuidePanel(
                title: .settingsExplorePlacesLocationsTitle,
                detail: .settingsExplorePlacesLocationsDetail,
                symbol: .mapFill,
            ) {
                if let region = report.ranking.primary.first {
                    RegionSummaryCard(
                        regionDays: region,
                        variant: .compact,
                        yearLength: report.daysInSelectedYear,
                        year: report.selectedYear,
                    )
                }
                if !report.ranking.secondary.isEmpty {
                    ElsewhereSummaryCard(regions: report.ranking.secondary.map(\.region))
                }
            }
            .featureMarketingRow(order: 1)
            .settingsRow(Item.locations, restingBackground: .clear)
            FeatureGuidePanel(
                title: .settingsExplorePlacesCalendarTitle,
                detail: .settingsExplorePlacesCalendarDetail,
                symbol: .calendar,
            ) {
                FeatureYearHistoryPreview(report: report)
            }
            .featureMarketingRow(order: 2)
            .settingsRow(Item.calendar, restingBackground: .clear)
            FeatureGuidePanel(
                title: .settingsExplorePlacesTimelineTitle,
                detail: .settingsExplorePlacesTimelineDetail,
                symbol: .calendarDayTimelineLeft,
            ) {
                PresenceTimelineList(report: report, presentation: .excerpt)
            }
            .featureMarketingRow(order: 3)
            .settingsRow(Item.timeline, restingBackground: .clear)
            FeatureGuidePanel(
                title: .settingsExplorePlacesWelcomeTitle,
                detail: .settingsExplorePlacesWelcomeDetail,
                symbol: .sparkles,
            ) {}
                .featureMarketingRow(order: 4)
                .settingsRow(Item.welcome, restingBackground: .clear)
            FeatureSettingsLink(destination: .year).featureMarketingRow(order: 5)
            FeatureSettingsLink(destination: .appearance).featureMarketingRow(order: 6)
        }
    }
}

extension PlacesYearFeaturesView: SettingsSection {
    static var destination: SettingsDestination {
        .placesYear
    }

    enum Item: SettingsItem {
        case locations
        case calendar
        case timeline
        case welcome

        var title: String {
            switch self {
                case .locations: String(localized: .settingsExplorePlacesLocationsTitle)
                case .calendar: String(localized: .settingsExplorePlacesCalendarTitle)
                case .timeline: String(localized: .settingsExplorePlacesTimelineTitle)
                case .welcome: String(localized: .settingsExplorePlacesWelcomeTitle)
            }
        }

        var keywords: [String] {
            switch self {
                case .locations: splitKeywords(
                        String(localized: .settingsExplorePlacesLocationsKeywords),
                    )
                case .calendar: splitKeywords(
                        String(localized: .settingsExplorePlacesCalendarKeywords),
                    )
                case .timeline: splitKeywords(
                        String(localized: .settingsExplorePlacesTimelineKeywords),
                    )
                case .welcome: splitKeywords(
                        String(localized: .settingsExplorePlacesWelcomeKeywords),
                    )
            }
        }
    }
}

#if DEBUG
    extension PlacesYearFeaturesView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Loaded", configurations: .fullContentScreenDefaults) {
                PlacesYearFeaturesView(
                    report: PreviewSupport.plannedStayYearReportModel(),
                    focus: nil,
                )
            }
            whereSnapshot(name: "Empty", configurations: .fullContentPhoneLightDark) {
                PlacesYearFeaturesView(report: PreviewSupport.emptyYearReportModel(), focus: nil)
            }
            whereSnapshot(name: "Unavailable", configurations: .fullContentPhoneLightDark) {
                PlacesYearFeaturesView(report: YearReportModel(
                    services: PreviewSupport.previewServices(),
                    selectedYear: PreviewSupport.year,
                    preferences: PreviewSupport.previewPreferences(),
                    now: { PreviewSupport.referenceNow },
                ), focus: nil)
            }
            whereSnapshot(name: "Demo", configurations: .fullContentPhoneLightDark) {
                PlacesYearFeaturesView(report: PreviewSupport.loadedYearReportModel(), focus: nil)
                    .environment(\.isInDemoMode, true)
            }
        }
    }

    #Preview {
        NavigationStack { PlacesYearFeaturesView.snapshotPreviews }
            .whereBroadwayRoot()
    }

    extension PlacesYearFeaturesView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            PlacesYearFeaturesView.self,
            title: "Your Places & Your Year",
            routes: [
                .push(to: VisibleYearSettingsView.flyoverID),
                .push(to: AppearanceSettingsView.flyoverID),
            ],
        )
    }
#endif
