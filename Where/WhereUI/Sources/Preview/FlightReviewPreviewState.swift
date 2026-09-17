#if DEBUG
    import Foundation
    import RegionKit
    @_spi(Testing) import WhereCore

    /// Deterministic production-shaped states shared by the notice and review snapshots.
    enum FlightReviewPreviewState: String, CaseIterable {
        case flightLikely = "FlightLikely"
        case waiting = "Waiting"
        case stale = "Stale"
        case ready = "Ready"
        case noPresence = "NoPresence"
        case completed = "Completed"
    }

    extension PreviewSupport {
        @MainActor
        static func flightYearReportModel(state: FlightReviewPreviewState) -> YearReportModel {
            let report = loadedYearReportModel()
            report.setDataIssueScan(flightScan(state: state))
            return report
        }

        static func flightScan(state: FlightReviewPreviewState) -> DataIssueScanResult {
            let review = flightReview(state: state)
            var issues: [any DataIssue] = []
            if let proposal = review.proposal {
                issues.append(SampleCorrectionIssue(proposal: proposal))
            }
            return DataIssueScanResult(
                revision: UUID(uuidString: "00000000-0000-0000-0000-000000000303")!,
                issues: issues,
                reviews: [review],
                nextReassessmentAt: review.flight?.nextReassessmentAt,
            )
        }

        @MainActor
        static func flightResolveModel(state: FlightReviewPreviewState) -> ResolveModel {
            let resolve = resolveModel(seededWithIssues: false)
            let scan = flightScan(state: state)
            resolve.setDataIssues(scan.issues)
            resolve.setReviews(scan.reviews)
            return resolve
        }

        static func borderDriftReview(date: Date) -> GPSCorrectionReview {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let day = DayPresence(date: date, in: calendar, regions: [.newYork, .other])
            let reviewID = DataIssueID.borderDrift(day: day.day)
            return GPSCorrectionReview(
                id: reviewID,
                day: day,
                points: [],
                state: .ready(SampleCorrectionProposal(
                    reviewID: reviewID,
                    day: day,
                    resultingRegions: [.newYork],
                    edits: [.init(
                        sampleID: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
                        replacementRegions: [.newYork],
                    )],
                ), flight: nil),
            )
        }

        static func flightReview(state: FlightReviewPreviewState) -> GPSCorrectionReview {
            flightReview(state: state, date: referenceNow)
        }

        static func flightReview(
            state: FlightReviewPreviewState,
            date: Date,
        ) -> GPSCorrectionReview {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let sampleID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
            let day = DayPresence(
                date: date,
                in: calendar,
                regions: state == .noPresence ? [.other] : [.california, .other, .newYork],
            )
            let reviewID = DataIssueID.flightDay(day: day.day)
            let progress: FlightAssessment.Progress = switch state {
                case .flightLikely: .flightLikely
                case .waiting, .stale: .awaitingArrival
                case .ready, .noPresence, .completed: .completed(arrivedAt: date)
            }
            let flight = FlightAssessment(
                id: .init(
                    recordingDeviceID: CurrentRecordingDevice.preview.id,
                    departureSampleID: sampleID,
                ),
                startedAt: date.addingTimeInterval(-5 * 60 * 60),
                lastObservationAt: date.addingTimeInterval(state == .stale ? -2 * 60 * 60 : 0),
                lastFlightAt: date.addingTimeInterval(-15 * 60),
                airborneSampleIDs: [sampleID],
                groundSampleIDs: [],
                peakSpeedKMH: 1040,
                progress: progress,
            )
            let reviewState: GPSCorrectionReview.State = switch state {
                case .flightLikely, .waiting, .stale:
                    .pending(flight)
                case .ready, .noPresence:
                    .ready(SampleCorrectionProposal(
                        reviewID: reviewID,
                        day: day,
                        resultingRegions: state == .noPresence ? [] : [.california, .newYork],
                        edits: [.init(sampleID: sampleID, replacementRegions: [])],
                    ), flight: flight)
                case .completed:
                    .completed(flight)
            }
            // No network-backed map in these fixtures. The same review body
            // renders evidence, arrival state, and sample-edit summary synchronously.
            return GPSCorrectionReview(id: reviewID, day: day, points: [], state: reviewState)
        }
    }
#endif
