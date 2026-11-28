import SwiftUI

struct JourneyDayCountBadge: View {
    let text: String
    let font: Font
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let fill: Color

    var body: some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background { Capsule().fill(fill) }
    }
}

#if DEBUG
    #Preview("Planned duration") {
        PresenceTimelineList(report: PreviewSupport.itineraryYearReportModel())
            .whereBroadwayRoot()
    }
#endif
