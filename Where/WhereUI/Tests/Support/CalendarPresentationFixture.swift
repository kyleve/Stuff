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
    let reveals: CalendarRevealTestSupport

    var body: some View {
        NavigationStack {
            Group {
                if fixture.showsTabletop {
                    CalendarContentView(
                        focusedRegion: fixture.region,
                        report: report,
                        monthReveal: reveals.binding,
                        presentation: .month,
                        persistenceKey: fixture.region.map(CalendarZoomKey.region),
                    )
                } else {
                    CalendarContentView(
                        focusedRegion: fixture.region,
                        report: report,
                        monthReveal: reveals.binding,
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
