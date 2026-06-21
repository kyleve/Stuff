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

    @Test func primaryViewHostsTheMissingDaysBanner() throws {
        let session = PreviewSupport.missingDaysSession()
        // The fixture must have gaps, otherwise the banner branch never renders.
        #expect(session.missingDayCount > 0)
        try show(UIHostingController(rootView: PrimaryView().environment(session))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func missingDaysViewHostsWithRanges() throws {
        let session = PreviewSupport.missingDaysSession()
        #expect(!session.missingDays.isEmpty)
        try show(UIHostingController(rootView: MissingDaysView().environment(session))) { hosted in
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

    @Test func appIconViewHosts() throws {
        let rootView = NavigationStack { AppIconView(model: .preview()) }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func appIconPreviewViewHosts() throws {
        try show(UIHostingController(rootView: AppIconPreviewProbe())) { hosted in
            #expect(hosted.view != nil)
        }
    }
}

/// Hosts `AppIconPreviewView`, which needs a `Namespace` from an enclosing view
/// to drive its zoom transition.
private struct AppIconPreviewProbe: View {
    @Namespace private var namespace

    var body: some View {
        AppIconPreviewView(
            option: AppIconOption(
                id: AppIconID("classic"),
                displayName: "Classic",
                alternateIconName: nil,
                previewImageName: "AppIconClassic",
            ),
            model: .preview(),
            namespace: namespace,
        )
    }
}
