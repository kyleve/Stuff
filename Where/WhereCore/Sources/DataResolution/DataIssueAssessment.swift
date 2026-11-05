import Foundation

/// Runs the same detectors and GPS assessment for annual and all-history publications.
/// It consumes immutable admitted reads and never writes a scanner cache.
struct DataIssueAssessment {
    private static let logger = WhereLog.reporting(DataIssueScannerLog.self)
    let calendar: Calendar
    let detectors: [any DataIssueDetecting]

    func scan(
        reads: DataIssueReads,
        driftThresholdMeters: Double,
        now currentDate: Date,
    ) throws -> DataIssueScanResult {
        try Task.checkCancellation()
        let input = DataIssueInput(
            year: reads.report.year,
            report: reads.report,
            otherDayCoordinates: reads.otherDayCoordinates,
            daySamples: reads.daySamples,
            primaryRegions: reads.primaryRegions,
            attributor: reads.attribution,
            driftThresholdMeters: driftThresholdMeters,
            calendar: calendar,
            now: currentDate,
        )
        let assessment = try Self.logger.measure(.assessGPS) {
            try SampleCorrectionAssessment(
                attributor: reads.correctionAttribution,
                calendar: calendar,
            )
            .assess(
                reads: reads,
                driftThresholdMeters: driftThresholdMeters,
                now: currentDate,
            )
        }
        let assessedReviews = assessment.reviews
        let otherIssues = try detectors.flatMap { detector in
            try Self.logger.measure(.detect(detector.detects)) {
                try detector.detectAnyIssues(in: input)
            }
        }
        let flightDays = Set(assessedReviews.filter { !$0.flights.isEmpty }.map(\.day.day))
        let unexplainedIssues = otherIssues.filter { issue in
            // Flight reviews own these transitions before and after
            // arrival, including their exact-sample correction. Do not
            // also offer a whole-day travel correction for that flight.
            guard case let .markTravelDay(earlier, later, _) = issue.resolution else {
                return true
            }
            return !flightDays.contains(earlier.day) && !flightDays.contains(later.day)
        }
        // Dismissal hides the proposal, retaining any unfinished flights
        // in that same review. Use all assessed flights above
        // so dismissal cannot revive an overlapping whole-day rewrite.
        let reviews = assessedReviews.compactMap {
            reads.dismissedIssueIDs.contains($0.id) ? $0.dismissingProposal() : $0
        }
        let gpsIssues: [any DataIssue] = reviews.compactMap { review in
            review.proposal.map { SampleCorrectionIssue(proposal: $0) }
        }
        let issues = Self.sortIssues((unexplainedIssues + gpsIssues).filter {
            !reads.dismissedIssueIDs.contains($0.id)
        })
        let deadlines = reviews.flatMap(\.flights).flatMap { flight in
            [
                flight.reassessment.scheduledDate,
                flight.lastObservationAt.addingTimeInterval(
                    GPSCorrectionPolicy.Presentation.liveNoticeRetentionInterval,
                ),
            ]
            .compactMap(\.self).filter { $0 > currentDate }
        }
        return DataIssueScanResult(
            revision: UUID(),
            completeness: reads.report.completeness,
            issues: issues,
            reviews: reviews,
            completedFlights: assessment.flights.filter {
                $0.completedDays(in: calendar).contains { $0.year == reads.report.year }
            },
            nextReassessmentAt: deadlines.min(),
        )
    }

    private static func sortIssues(_ issues: [any DataIssue]) -> [any DataIssue] {
        issues.sorted { lhs, rhs in
            let lhsOrder = DataIssueCategory.allCases.firstIndex(of: lhs.category) ?? 0
            let rhsOrder = DataIssueCategory.allCases.firstIndex(of: rhs.category) ?? 0
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.sortKey < rhs.sortKey
        }
    }
}
