import LogViewerUI
import SwiftUI
import Testing
import WhereCore
import WhereTesting
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
        // Settings reads the app model (reset) and the logged-in session (tracking
        // + inspector) from the environment, and takes the scene report explicitly.
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
        let day = DayPresence(date: .now, regions: [.other])
        let rootView = NavigationStack { DayRelabelView(day: day, report: report) }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
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

    @Test func manualDayEntryViewHostsDefault() throws {
        let report = PreviewSupport.loadedYearReportModel()
        let rootView = NavigationStack { ManualDayEntryView(report: report) }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func manualDayEntryViewHostsPrefill() throws {
        let report = PreviewSupport.missingDaysYearReportModel()
        let range = try #require(report.missingDays.first)
        let rootView = NavigationStack { ManualDayEntryView(report: report, prefill: range) }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func debugLogViewerHostsWithSharedStore() throws {
        // The Settings debug entry pushes this viewer over WhereLog's buffer.
        let rootView = NavigationStack {
            LogViewer(configuration: LogViewerConfiguration(store: WhereLog.store, title: "Logs"))
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
