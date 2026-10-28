import SwiftUI

/// Keeps the flight link and its destination behind one small value boundary.
struct LocationsFlightNotice: View {
    let report: YearReportModel

    var body: some View {
        if let review = report.liveFlightReview {
            NavigationLink {
                FlightDayDetailView(review: review, report: report)
            } label: {
                FlightStatusBanner(
                    review: review,
                    deviceLabel: report.liveFlightAssessment(in: review)
                        .map(report.flightDeviceLabel),
                    flight: report.liveFlightAssessment(in: review),
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(localized: .flightStatusOpenReview))
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            LocationsFlightNotice(report: PreviewSupport
                .flightYearReportModel(state: .flightLikely))
        }
        .whereBroadwayRoot()
    }
#endif
