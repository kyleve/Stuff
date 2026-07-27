import RegionKit
import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct RegionSummaryCardTests {
    /// A region card's count can change with the card on screen, which runs an
    /// animated morph (`CardStyles.DayCountStyle`) rather than a cut — so
    /// re-render one with a new count and confirm the card survives the update.
    @Test func hostsAChangingDayCount() throws {
        func card(days: Int) -> RegionSummaryCard {
            RegionSummaryCard(regionDays: RegionDays(region: .california, days: days), year: 2026)
        }

        try show(UIHostingController(rootView: card(days: 148))) { hosted in
            hosted.rootView = card(days: 149)
            hosted.view.layoutIfNeeded()
            #expect(hosted.view != nil)
        }
    }
}
