import SwiftUI
import WhereCore

/// A completed flight on the same connected rail as recorded and planned stays.
struct FlightJourneyRow: View {
    let flight: FlightAssessment
    let calendar: Calendar
    let isFirst: Bool
    let isLast: Bool

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        if case let .completed(arrivedAt) = flight.progress {
            HStack(spacing: stylesheet.timeline.rail.toCardSpacing) {
                Color.clear.frame(width: stylesheet.timeline.rail.nodeSize)
                VStack(alignment: .leading, spacing: stylesheet.timeline.flight.labelSpacing) {
                    Text(.historyFlight).font(.subheadline.bold())
                    Text(DateRangeFormatting.abbreviated(
                        start: flight.startedAt,
                        end: arrivedAt,
                        calendar: calendar,
                    ))
                    .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, stylesheet.timeline.flight.verticalPadding)
            .background(alignment: .leading) {
                PresenceJourneyRail(
                    tint: stylesheet.timeline.flight.tint,
                    marker: .flight,
                    isFirst: isFirst,
                    isLast: isLast,
                )
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#if DEBUG
    #Preview {
        PresenceTimelineList(report: PreviewSupport.flightYearReportModel(state: .completed))
            .whereBroadwayRoot()
    }
#endif
