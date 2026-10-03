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
                revision: .init(
                    rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000303")!,
                ),
                issues: issues,
                reviews: [review],
                nextReassessmentAt: review.flight?.reassessment.scheduledDate,
            )
        }

        @MainActor
        static func flightResolveModel(state: FlightReviewPreviewState) -> ResolveModel {
            ResolveModel(
                services: previewServices(),
                source: FixtureResolutionSource(scan: flightScan(state: state)),
            )
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
                    kind: .borderDrift,
                    day: day,
                    resultingRegions: [.newYork],
                    edits: [.init(
                        sampleID: .init(
                            rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
                        ),
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
            let coordinates = [
                Coordinate(latitude: 37.6213, longitude: -122.3790),
                Coordinate(latitude: 39.53, longitude: -106.16),
                Coordinate(latitude: 41.2, longitude: -95.9),
                Coordinate(latitude: 41.3, longitude: -84.1),
                Coordinate(latitude: 40.6413, longitude: -73.7781),
            ]
            let visibleIndices: [Int] = switch state {
                case .flightLikely, .waiting, .stale: [0, 1, 2]
                case .noPresence: [1, 2, 3]
                case .ready, .completed: [0, 1, 2, 3, 4]
            }
            let points = visibleIndices.map { index in
                let region: Region = switch index {
                    case 0: .california
                    case 4: .newYork
                    default: .other
                }
                return SampleCorrectionPoint(
                    sample: LocationSample(
                        id: .init(rawValue: UUID(uuidString: String(
                            format: "00000000-0000-0000-0000-%012d",
                            300 + index,
                        ))!),
                        timestamp: date.addingTimeInterval(Double(index - 4) * 3600),
                        coordinate: coordinates[index],
                        horizontalAccuracy: 30,
                        source: .gpsSignificantChange,
                        recordingDeviceID: CurrentRecordingDevice.preview.id,
                    ),
                    regions: state == .completed && region == .other ? [] : [region],
                )
            }
            let airborne = Set(points.filter { $0.regions.contains(.other) || $0.regions.isEmpty }
                .map(\.sample.id))
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
                    recordingSource: .device(CurrentRecordingDevice.preview.id),
                    departureSampleID: points[0].sample.id,
                ),
                startedAt: date.addingTimeInterval(-5 * 60 * 60),
                lastObservationAt: date.addingTimeInterval(state == .stale ? -2 * 60 * 60 : 0),
                lastFlightAt: date.addingTimeInterval(-15 * 60),
                airborneSampleIDs: airborne,
                groundSampleIDs: Set(points.map(\.sample.id)).subtracting(airborne),
                peakSpeedKMH: 1040,
                progress: progress,
            )
            let reviewState: GPSCorrectionReview.State = switch state {
                case .flightLikely, .waiting, .stale:
                    .pending(flight)
                case .ready, .noPresence:
                    .ready(SampleCorrectionProposal(
                        kind: .flight,
                        day: day,
                        resultingRegions: state == .noPresence ? [] : [.california, .newYork],
                        edits: points.filter { airborne.contains($0.sample.id) }.map {
                            .init(sampleID: $0.sample.id, replacementRegions: [])
                        },
                    ), flight: flight)
                case .completed:
                    .completed(flight)
            }
            return GPSCorrectionReview(id: reviewID, day: day, points: points, state: reviewState)
        }
    }
#endif
