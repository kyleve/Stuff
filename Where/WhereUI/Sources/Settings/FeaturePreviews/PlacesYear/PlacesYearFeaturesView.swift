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
            let cache = PreviewSupport.snapshotArtworkCache
            let loaded = PreviewSupport.plannedStayYearReportModel()
            let demo = PreviewSupport.loadedYearReportModel()
            whereSnapshot(
                name: "Loaded",
                configurations: .fullContentPhoneLightDarkWithAX5,
                onReadyToMeasure: {
                    if let input = loaded.elsewhereInput {
                        await loaded.elsewhere.refresh(input)
                    }
                },
                onReadyToSnapshot: {
                    await PreviewSupport.loadCardArtwork(
                        for: loaded.locationRegions.map(\.region)
                            + (loaded.elsewhere.content(for: loaded.selectedYear)?.regions
                                .map(\.region) ?? []),
                        cache: cache,
                    )
                },
            ) {
                PlacesYearFeaturesView(
                    report: loaded,
                    focus: nil,
                )
                .environment(\.regionOutlinePathCache, cache)
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
                    if let input = demo.elsewhereInput {
                        await demo.elsewhere.refresh(input)
                    }
                },
                onReadyToSnapshot: {
                    await PreviewSupport.loadCardArtwork(
                        for: demo.locationRegions.map(\.region)
                            + (demo.elsewhere.content(for: demo.selectedYear)?.regions
                                .map(\.region) ?? []),
                        cache: cache,
                    )
                },
            ) {
                PlacesYearFeaturesView(report: demo, focus: nil)
                    .environment(\.isInDemoMode, true)
                    .environment(\.regionOutlinePathCache, cache)
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

/// Builds gallery rows below the page's reveal and focus scopes so those scopes
/// store only this small view, rather than the complete concrete row tree.
private struct PlacesYearFeaturesContent: View {
    let report: YearReportModel

    var body: some View {
        PlacesLocationsGuideRow(report: report)
        PlacesCalendarGuideRow(report: report)
        PlacesTimelineGuideRow(report: report)
        FeatureGuideExplanationRow(
            title: .settingsExplorePlacesWelcomeTitle,
            detail: .settingsExplorePlacesWelcomeDetail,
            symbol: .sparkles,
            item: PlacesYearFeaturesView.Item.welcome,
            order: 4,
        )
        FeatureSettingsLink(destination: .year).featureMarketingRow(order: 5)
        FeatureSettingsLink(destination: .appearance).featureMarketingRow(order: 6)
    }
}

private struct PlacesLocationsGuideRow: View {
    let report: YearReportModel

    var body: some View {
        FeatureGuidePanel(
            title: .settingsExplorePlacesLocationsTitle,
            detail: .settingsExplorePlacesLocationsDetail,
            symbol: .mapFill,
        ) {
            PlacesTrackedRegionExample(report: report)
            PlacesElsewhereRegionExample(report: report)
        }
        .task(id: report.elsewhereInput) {
            if let input = report.elsewhereInput {
                await report.elsewhere.refresh(input)
            }
        }
        .featureMarketingRow(order: 1)
        .settingsRow(PlacesYearFeaturesView.Item.locations, restingBackground: .clear)
    }
}

private struct PlacesTrackedRegionExample: View {
    let report: YearReportModel

    var body: some View {
        if let region = report.locationRegions.first {
            RegionSummaryCard(
                regionDays: region,
                variant: .compact,
                yearLength: report.daysInSelectedYear,
                year: report.selectedYear,
            )
        }
    }
}

private struct PlacesElsewhereRegionExample: View {
    let report: YearReportModel

    var body: some View {
        if let content = report.elsewhere.content(for: report.selectedYear),
           let region = content.regions.first
        {
            RegionSummaryCard(
                regionDays: RegionDays(region: region.region, days: region.days.count),
                variant: .elsewhere,
                year: report.selectedYear,
                recordedPoints: content.cardLocations.pointsByRegion[region.region] ?? [],
                showsRecordedPoints: report.showsRecordedLocationDots,
                recordedPointsID: content.cardLocations.id,
            )
        }
    }
}

private struct PlacesTimelineGuideRow: View {
    let report: YearReportModel

    var body: some View {
        FeatureGuidePanel(
            title: .settingsExplorePlacesTimelineTitle,
            detail: .settingsExplorePlacesTimelineDetail,
            symbol: .calendarDayTimelineLeft,
        ) {
            PresenceTimelineList(report: report, presentation: .excerpt)
        }
        .featureMarketingRow(order: 3)
        .settingsRow(PlacesYearFeaturesView.Item.timeline, restingBackground: .clear)
    }
}

#if DEBUG
    #Preview("Places Year Features Content") {
        NavigationStack {
            PlacesYearFeaturesView(report: PreviewSupport.plannedStayYearReportModel(), focus: nil)
        }
        .whereBroadwayRoot()
    }
#endif
