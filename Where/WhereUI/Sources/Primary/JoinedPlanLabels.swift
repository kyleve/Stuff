import SwiftUI

struct JoinedPlanLabels: View {
    let regionName: String
    let dateRange: String
    let row: WhereStylesheet.TimelineStyle.Row
    let planned: WhereStylesheet.TimelineStyle.Planned

    var body: some View {
        if row.stacksDayCount {
            VStack(alignment: .leading, spacing: row.labelSpacing) {
                Text(regionName)
                    .font(.subheadline.bold())
                Text(dateRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: planned.joinedLabelSpacing) {
                Text(regionName)
                    .font(.subheadline.bold())
                    .layoutPriority(1)
                Text(dateRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
    #Preview("Joined plan") {
        PresenceTimelineList(report: PreviewSupport.itineraryYearReportModel())
            .whereBroadwayRoot()
    }
#endif
