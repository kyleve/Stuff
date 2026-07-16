import PeriscopeCore
import PeriscopeTools
import RegionKit
import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

/// Hosts each top-level screen in a real window with seeded preview data to
/// confirm the Liquid Glass layouts mount without crashing. Report/year screens
/// take a `YearReportModel` explicitly (constructor injection); the always-on views
/// (Settings) also read the `WhereSession` coordinator from the environment.
@MainActor
struct ScreenHostingTests {
    @Test func primaryViewHostsWithData() throws {
        let report = PreviewSupport.loadedYearReportModel()
        try show(UIHostingController(rootView: PrimaryView(report: report))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func secondaryViewHostsWithData() throws {
        let report = PreviewSupport.loadedYearReportModel()
        try show(UIHostingController(rootView: SecondaryView(report: report))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func settingsViewHosts() throws {
        // Settings reads the app model (reset) and the logged-in session
        // (tracking) from the environment, and takes the scene report explicitly.
        let model = PreviewSupport.loadedModel()
        let session = PreviewSupport.loadedSession()
        let rootView = SettingsView(report: PreviewSupport.loadedYearReportModel())
            .environment(model)
            .environment(session)
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func primaryViewHostsWithElsewhereOnlyData() throws {
        let report = PreviewSupport.elsewhereOnlyYearReportModel()
        try show(UIHostingController(rootView: PrimaryView(report: report))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func primaryViewHostsWithMissingDays() throws {
        let report = PreviewSupport.missingDaysYearReportModel()
        try show(UIHostingController(rootView: PrimaryView(report: report))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func resolutionViewHostsWithIssues() throws {
        let resolve = PreviewSupport.resolveModel()
        #expect(!resolve.dataIssues.isEmpty)
        let rootView = ResolutionView(
            report: PreviewSupport.loadedYearReportModel(),
            resolve: resolve,
        )
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func resolutionViewHostsEmpty() throws {
        let resolve = PreviewSupport.resolveModel(seededWithIssues: false)
        let rootView = ResolutionView(
            report: PreviewSupport.loadedYearReportModel(),
            resolve: resolve,
        )
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func regionDaysViewHostsWithData() throws {
        // `elsewhereOnlyYearReportModel` has only `.other` days, so the drill-in list
        // for that region has rows to render.
        let report = PreviewSupport.elsewhereOnlyYearReportModel()
        let rootView = NavigationStack { RegionDaysView(region: .other, report: report) }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func regionMapViewHosts() throws {
        // Self-contained — reads geometry from RegionGeometryCatalog, so
        // it needs no session/environment.
        let rootView = NavigationStack { RegionMapView() }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func dayRelabelViewHosts() throws {
        let report = PreviewSupport.loadedYearReportModel()
        let day = DayPresence(date: .now, in: .current, regions: [.other])
        let rootView = NavigationStack { DayRelabelView(day: day, report: report) }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func dayRelabelViewHostsWithAuditRecord() throws {
        let report = PreviewSupport.loadedYearReportModel()
        let day = DayPresence(
            date: .now,
            in: .current,
            regions: [.california],
            isAuthoritative: true,
            audit: ManualEntryAudit(
                recordedAt: .now,
                note: "Corrected after reviewing my boarding pass.",
                location: CapturedLocation(
                    coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                    horizontalAccuracy: 12,
                    timestamp: .now,
                ),
            ),
        )
        let rootView = NavigationStack { DayRelabelView(day: day, report: report) }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func recentActivitySummaryViewHostsEachState() throws {
        for state in [
            RecentActivityModel.LoadState.loaded("You were in California, then New York."),
            .empty,
            .unavailable(.appleIntelligenceNotEnabled),
            .failed("Something went wrong."),
        ] {
            let rootView = RecentActivitySummaryView(
                model: PreviewSupport.recentActivityModel(state: state),
            )
            try show(UIHostingController(rootView: rootView)) { hosted in
                #expect(hosted.view != nil)
            }
        }
    }

    @Test func presenceTimelineViewHostsWithData() throws {
        let report = PreviewSupport.loadedYearReportModel()
        try show(UIHostingController(rootView: PresenceTimelineView(report: report))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func calendarViewHostsWithData() throws {
        let report = PreviewSupport.loadedYearReportModel()
        try show(UIHostingController(rootView: CalendarView(report: report))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func appIconViewHosts() throws {
        let rootView = NavigationStack { AppIconView(model: .preview()) }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func loggedDaysViewHostsEachState() throws {
        for state in [
            LoggedDaysModel.LoadState.loaded(PreviewSupport.sampleManualDays()),
            .empty,
            .failed("iCloud is unavailable."),
        ] {
            let rootView = LoggedDaysView(
                report: PreviewSupport.loadedYearReportModel(),
                model: PreviewSupport.loggedDaysModel(state: state),
            )
            try show(UIHostingController(rootView: rootView)) { hosted in
                #expect(hosted.view != nil)
            }
        }
    }

    @Test func manualDayViewHostsAddModes() throws {
        let report = PreviewSupport.loadedYearReportModel()
        for showsCancel in [false, true] {
            let rootView = NavigationStack {
                ManualDayView(
                    report: report,
                    mode: .add(prefill: nil),
                    showsCancelButton: showsCancel,
                )
            }
            try show(UIHostingController(rootView: rootView)) { hosted in
                #expect(hosted.view != nil)
            }
        }

        // Prefilled-range add (the Resolve backfill flow).
        let missing = PreviewSupport.missingDaysYearReportModel()
        let range = try #require(missing.missingDays.first)
        let prefilled = NavigationStack {
            ManualDayView(report: missing, mode: .add(prefill: range))
        }
        try show(UIHostingController(rootView: prefilled)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func manualDayViewHostsEditModes() throws {
        let report = PreviewSupport.loadedYearReportModel()
        let days = [
            DayPresence(date: .now, in: .current, regions: [.california]),
            DayPresence(
                date: .now,
                in: .current,
                regions: [.canada],
                isAuthoritative: true,
                audit: ManualEntryAudit(recordedAt: .now, note: "Boarding pass.", location: nil),
            ),
        ]
        for day in days {
            let rootView = NavigationStack {
                ManualDayView(report: report, mode: .edit(day), showsCancelButton: true)
            }
            try show(UIHostingController(rootView: rootView)) { hosted in
                #expect(hosted.view != nil)
            }
        }
    }

    @Test func periscopeViewerHostsOverTheLogStore() async throws {
        // The developer tools surface pushes this viewer over the process-global
        // Periscope store.
        let store = try await PeriscopeStore.make(storage: .inMemory, session: .current())
        let rootView = NavigationStack {
            PeriscopeViewer(store: store, title: "Logs")
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func openSpansViewHosts() throws {
        // The open-spans monitor reads the shared system directly.
        let rootView = NavigationStack {
            OpenSpansView(system: .shared)
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func developerToolsViewHosts() async throws {
        // Reads the app model (for the log store) and the logged-in session (for
        // the SwiftData inspector row) from the environment; owns its own
        // navigation stack for the pushed viewers.
        let store = try await PeriscopeStore.make(storage: .inMemory, session: .current())
        let rootView = DeveloperToolsView()
            .environment(PreviewSupport.loadedModel(withLogStore: store))
            .environment(PreviewSupport.loadedSession())
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func developerOverlayHosts() throws {
        // The floating overlay mounts (collapsed) with a session available for the
        // tools it can expand into.
        let rootView = DeveloperOverlay()
            .environment(PreviewSupport.loadedModel())
            .environment(PreviewSupport.loadedSession())
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
