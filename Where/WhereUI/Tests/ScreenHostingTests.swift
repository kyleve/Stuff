import LogViewerUI
import SwiftUI
import Testing
import WhereCore
import WhereTesting
@testable import WhereUI

/// Hosts each top-level screen in a real window with seeded preview data to
/// confirm the Liquid Glass layouts mount without crashing.
@MainActor
struct ScreenHostingTests {
    @Test func primaryViewHostsWithData() throws {
        let session = PreviewSupport.loadedSession()
        try show(UIHostingController(rootView: PrimaryView().environment(session))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func secondaryViewHostsWithData() throws {
        let session = PreviewSupport.loadedSession()
        try show(UIHostingController(rootView: SecondaryView().environment(session))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func settingsViewHosts() throws {
        // Settings reads both the app model (reset) and the logged-in session.
        let model = PreviewSupport.loadedModel()
        let session = PreviewSupport.loadedSession()
        let rootView = SettingsView()
            .environment(model)
            .environment(session)
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func primaryViewHostsWithElsewhereOnlyData() throws {
        let session = PreviewSupport.elsewhereOnlySession()
        try show(UIHostingController(rootView: PrimaryView().environment(session))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func primaryViewHostsWithMissingDaysSession() throws {
        let session = PreviewSupport.missingDaysSession()
        try show(UIHostingController(rootView: PrimaryView().environment(session))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func resolutionViewHostsWithIssues() throws {
        let session = PreviewSupport.resolutionSession()
        #expect(session.dataIssueCount > 0)
        try show(UIHostingController(rootView: ResolutionView().environment(session))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func resolutionViewHostsEmpty() throws {
        let session = PreviewSupport.loadedSession()
        try show(UIHostingController(rootView: ResolutionView().environment(session))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func regionDaysViewHostsWithData() throws {
        // `elsewhereOnlySession` has only `.other` days, so the drill-in list
        // for that region has rows to render.
        let session = PreviewSupport.elsewhereOnlySession()
        let rootView = NavigationStack { RegionDaysView(region: .other) }
            .environment(session)
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func dayRelabelViewHosts() throws {
        let session = PreviewSupport.loadedSession()
        let day = DayPresence(date: .now, regions: [.other])
        let rootView = NavigationStack { DayRelabelView(day: day) }
            .environment(session)
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func presenceTimelineViewHostsWithData() throws {
        let session = PreviewSupport.loadedSession()
        try show(UIHostingController(rootView: PresenceTimelineView()
                .environment(session)))
        { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func calendarViewHostsWithData() throws {
        let session = PreviewSupport.loadedSession()
        try show(UIHostingController(rootView: CalendarView().environment(session))) { hosted in
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
        let session = PreviewSupport.loadedSession()
        let rootView = NavigationStack { ManualDayEntryView() }
            .environment(session)
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func manualDayEntryViewHostsPrefill() throws {
        let session = PreviewSupport.missingDaysSession()
        let range = try #require(session.missingDays.first)
        let rootView = NavigationStack { ManualDayEntryView(prefill: range) }
            .environment(session)
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
