import SwiftUI
import WhereCore

struct FlightJourneyDetails: View {
    let flight: FlightAssessment
    let arrival: FlightAssessment.Arrival
    let calendar: Calendar
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.timeline.flight.labelSpacing) {
            Text(.historyFlight).font(.subheadline.bold())
            ForEach(
                Array(flight.supportedPeriods.enumerated()),
                id: \.offset,
            ) { _, period in
                Text(DateRangeFormatting.abbreviated(
                    start: period.start,
                    end: period.end,
                    calendar: calendar,
                ))
                .font(.caption).foregroundStyle(.secondary)
            }
            if arrival.isTimingUncertain {
                Text(.flightStatusUncertainTitle)
                    .font(.caption).foregroundStyle(.secondary)
                Text(String(localized: .flightStatusGroundObserved(arrival.firstGroundAt
                        .formatted(.dateTime.month(.abbreviated).day().hour().minute()))))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
    #Preview {
        PresenceTimelineList(report: PreviewSupport.flightYearReportModel(state: .completed))
            .whereBroadwayRoot()
    }
#endif
