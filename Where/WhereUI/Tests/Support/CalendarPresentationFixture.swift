import BroadwayUI
import Observation
import RegionKit
import SwiftUI
import WhereCore
@testable import WhereUI

@MainActor @Observable
final class CalendarPresentationFixture {
    var showsTabletop = false
    var region: Region?
}

/// Separate layout branches recreate the production calendar under one retained scope.
struct CalendarPresentationHarness: View {
    let fixture: CalendarPresentationFixture
    let report: YearReportModel
    let history: PresenceSelectionModel

    var body: some View {
        NavigationStack {
            Group {
                if fixture.showsTabletop {
                    CalendarContentView(
                        focusedRegion: fixture.region,
                        report: report,
                        history: history,
                        presentation: .month,
                        persistenceKey: fixture.region.map(CalendarZoomKey.region),
                    )
                } else {
                    CalendarContentView(
                        focusedRegion: fixture.region,
                        report: report,
                        history: history,
                        persistenceKey: fixture.region.map(CalendarZoomKey.region),
                    )
                }
            }
            .id(fixture.region)
        }
        .whereBroadwayRoot()
        .bScrollRestorationScope()
    }
}
