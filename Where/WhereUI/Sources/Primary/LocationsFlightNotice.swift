import SwiftUI
import WhereCore

/// Keeps the flight link and its destination behind one small value boundary.
struct LocationsFlightNotice: View {
    let report: YearReportModel
    var openReview: ((GPSCorrectionReview) -> Void)?

    var body: some View {
        if let review = report.liveFlightReview {
            let banner = FlightStatusBanner(
                review: review,
                deviceLabel: report.liveFlightAssessment(in: review).map(report.flightDeviceLabel),
                flight: report.liveFlightAssessment(in: review),
            )
            Group {
                if let openReview {
                    Button { openReview(review) } label: { banner }
                } else {
                    NavigationLink { FlightDayDetailView(review: review, report: report) } label: {
                        banner
                    }
                }
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
