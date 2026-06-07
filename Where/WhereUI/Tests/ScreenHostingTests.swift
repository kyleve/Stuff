import SwiftUI
import Testing
import WhereTesting
@testable import WhereUI

/// Hosts each top-level screen in a real window with seeded preview data to
/// confirm the Liquid Glass layouts mount without crashing.
@MainActor
struct ScreenHostingTests {
    @Test func primaryViewHostsWithData() throws {
        let model = PreviewSupport.loadedModel()
        try show(UIHostingController(rootView: PrimaryView().environment(model))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func secondaryViewHostsWithData() throws {
        let model = PreviewSupport.loadedModel()
        try show(UIHostingController(rootView: SecondaryView().environment(model))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func settingsViewHosts() throws {
        let model = PreviewSupport.loadedModel()
        try show(UIHostingController(rootView: SettingsView().environment(model))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func primaryViewHostsWithElsewhereOnlyData() throws {
        let model = PreviewSupport.elsewhereOnlyModel()
        try show(UIHostingController(rootView: PrimaryView().environment(model))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func primaryViewHostsTheMissingDaysBanner() throws {
        let model = PreviewSupport.missingDaysModel()
        // The fixture must have gaps, otherwise the banner branch never renders.
        #expect(model.missingDayCount > 0)
        try show(UIHostingController(rootView: PrimaryView().environment(model))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func missingDaysViewHostsWithRanges() throws {
        let model = PreviewSupport.missingDaysModel()
        #expect(!model.missingDays.isEmpty)
        try show(UIHostingController(rootView: MissingDaysView().environment(model))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func presenceTimelineViewHostsWithData() throws {
        let model = PreviewSupport.loadedModel()
        try show(UIHostingController(rootView: PresenceTimelineView()
                .environment(model)))
        { hosted in
            #expect(hosted.view != nil)
        }
    }
}
