import SFSafeSymbols
import SwiftUI

struct TimelinePlanningButton: View {
    let action: () -> Void

    var body: some View {
        Button(
            String(localized: .plannedStaysTitle),
            systemSymbol: .calendarBadgeClock,
            action: action,
        )
    }
}

#if DEBUG
    #Preview("Timeline") {
        PresenceTimelineList(report: PreviewSupport.itineraryYearReportModel())
            .whereBroadwayRoot()
    }
#endif
