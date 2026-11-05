import SwiftUI
import WhereCore

/// A completed flight on the same connected rail as recorded and planned stays.
struct FlightJourneyRow: View {
    let flight: FlightAssessment
    let calendar: Calendar
    let isFirst: Bool
    let isLast: Bool

    @Environment(\.stylesheet) private var stylesheet

    /// Recording labels are already resolved. Never interpolate dates skipped during travel.
    var dateLabels: [String] {
        guard !flight.isPending else { return [] }
        return switch flight.dayBasis {
            case .viewingCalendar:
                flight.supportedPeriods.map {
                    DateRangeFormatting.abbreviated(
                        start: $0.start,
                        end: $0.end,
                        calendar: calendar,
                    )
                }
            case let .recording(days):
                days.sorted().map { DateRangeFormatting.abbreviated(start: $0, end: $0) }
        }
    }

    var body: some View {
        if case let .completed(arrival) = flight.progress {
            HStack(spacing: stylesheet.timeline.rail.toCardSpacing) {
                Color.clear.frame(width: stylesheet.timeline.rail.nodeSize)
                VStack(alignment: .leading, spacing: stylesheet.timeline.flight.labelSpacing) {
                    Text(.historyFlight).font(.subheadline.bold())
                    ForEach(
                        Array(dateLabels.enumerated()),
                        id: \.offset,
                    ) { _, label in
                        Text(label)
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
