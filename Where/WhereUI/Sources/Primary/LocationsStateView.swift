import SwiftUI
import WhereCore

/// Bounds loading, failure, and empty-state construction separately from the
/// navigation shell. Keep the state payload behind its own view boundary.
struct LocationsStateView: View {
    let report: YearReportModel
    let planningAction: () -> Void
    var openReview: ((GPSCorrectionReview) -> Void)?
    var openElsewhere: (() -> Void)?

    @Environment(\.stylesheet.spacing) private var spacing

    var body: some View {
        ScrollView {
            VStack(spacing: spacing.xxLarge) {
                LocationsFlightNotice(report: report, openReview: openReview)
                LocationsStateContent(
                    report: report,
                    planningAction: planningAction,
                    openElsewhere: openElsewhere,
                )
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(report.liveFlightReview == nil ? .center : .top, for: .alignment)
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            LocationsStateView(report: PreviewSupport.emptyYearReportModel(), planningAction: {})
        }
        .whereBroadwayRoot()
    }
#endif
