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
            PlacesYearFeaturesContent(report: report)
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
            let loaded = PreviewSupport.plannedStayYearReportModel()
            let demo = PreviewSupport.loadedYearReportModel()
            whereSnapshot(
                name: "Loaded",
                configurations: .fullContentScreenDefaults,
                onReadyToMeasure: {
                    if let input = loaded.elsewhereInput { await loaded.elsewhere.refresh(input) }
                },
            ) {
                PlacesYearFeaturesView(
                    report: loaded,
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
            whereSnapshot(
                name: "Demo",
                configurations: .fullContentPhoneLightDark,
                onReadyToMeasure: {
                    if let input = demo.elsewhereInput { await demo.elsewhere.refresh(input) }
                },
            ) {
                PlacesYearFeaturesView(report: demo, focus: nil)
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
