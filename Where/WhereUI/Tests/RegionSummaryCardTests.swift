import RegionKit
import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct RegionSummaryCardTests {
    @Test func artworkLoadIDSeparatesStaticArtworkFromPointRefreshes() throws {
        let recordedPointsID = try #require(
            PreviewSupport.loadedYearReportModel().primaryRegionLocations?.id,
        )
        let refreshedPointsID = try #require(
            PreviewSupport.loadedYearReportModel().primaryRegionLocations?.id,
        )
        let disabled = RegionArtworkLoadID(
            region: .newYork,
            variant: .regular,
            isEnabled: false,
            showsRecordedPoints: true,
            recordedPointsID: recordedPointsID,
        )
        let enabled = RegionArtworkLoadID(
            region: .newYork,
            variant: .regular,
            isEnabled: true,
            showsRecordedPoints: true,
            recordedPointsID: recordedPointsID,
        )
        let compact = RegionArtworkLoadID(
            region: .newYork,
            variant: .compact,
            isEnabled: true,
            showsRecordedPoints: true,
            recordedPointsID: recordedPointsID,
        )
        let refreshed = RegionArtworkLoadID(
            region: .newYork,
            variant: .regular,
            isEnabled: true,
            showsRecordedPoints: true,
            recordedPointsID: refreshedPointsID,
        )
        let pointsHidden = RegionArtworkLoadID(
            region: .newYork,
            variant: .regular,
            isEnabled: true,
            showsRecordedPoints: false,
            recordedPointsID: recordedPointsID,
        )
        let differentRegion = RegionArtworkLoadID(
            region: .california,
            variant: .regular,
            isEnabled: true,
            showsRecordedPoints: true,
            recordedPointsID: recordedPointsID,
        )

        #expect(disabled != enabled)
        #expect(enabled != compact)
        #expect(enabled != refreshed)
        #expect(enabled != pointsHidden)
        #expect(disabled.staticArtworkID != enabled.staticArtworkID)
        #expect(enabled.staticArtworkID != compact.staticArtworkID)
        #expect(enabled.staticArtworkID != differentRegion.staticArtworkID)
        #expect(enabled.staticArtworkID == refreshed.staticArtworkID)
        #expect(enabled.staticArtworkID == pointsHidden.staticArtworkID)
    }

    /// A region card's count can change with the card on screen, which runs an
    /// animated morph (`CardStyles.DayCountStyle`) rather than a cut — so
    /// re-render one with a new count and confirm the card survives the update.
    @Test func hostsAChangingDayCount() throws {
        func card(days: Int) -> RegionSummaryCard {
            RegionSummaryCard(regionDays: RegionDays(region: .california, days: days), year: 2026)
        }

        try show(UIHostingController(rootView: card(days: 148).whereBroadwayRoot())) { hosted in
            hosted.rootView = card(days: 149).whereBroadwayRoot()
            hosted.view.layoutIfNeeded()
            #expect(hosted.view != nil)
        }
    }
}
