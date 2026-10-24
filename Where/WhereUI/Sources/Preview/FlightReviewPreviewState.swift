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
        case uncertainArrival = "UncertainArrival"
    }

    extension PreviewSupport {
        /// A short visit interrupts a longer stay before a shared flight day.
        @MainActor
        static func interruptedStayYearReportModel() -> YearReportModel {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/New_York")!
            let days = (13 ... 23).map { day in
                var regions: Set<Region> = []
                if day <= 20 { regions.insert(.newYork) }
                if day == 14 { regions.insert(.other) }
                if day >= 20 { regions.insert(.california) }
                return DayPresence(
                    day: CalendarDay(year: year, month: 9, day: day),
                    regions: regions,
                )
            }
            let now = CalendarDay(year: year, month: 9, day: 23).startOfDay(in: calendar)
            let report = DayAggregator(calendar: calendar, timeZone: calendar.timeZone)
                .report(for: year, history: [], manualDays: days)
            let model = YearReportModel(
                services: previewServices(),
                details: YearReportDetails(
                    primaryRegions: [.california, .newYork],
                    report: report,
                    primaryRegionLocations: [:],
                ),
                selectedYear: year,
                preferences: previewPreferences(),
                now: { now },
            )
            let departure = calendar.date(from: DateComponents(
                year: year,
                month: 9,
                day: 20,
                hour: 12,
            ))!
            let arrival = calendar.date(byAdding: .hour, value: 6, to: departure)!
            let flight = FlightAssessment(
                id: .init(
                    recordingSource: .legacy,
                    departureSampleID: UUID(uuidString: "00000000-0000-0000-0000-000000000802")!,
                ),
                startedAt: departure,
                lastObservationAt: arrival,
                lastFlightAt: departure,
                airborneSampleIDs: [],
                groundSampleIDs: [],
                peakSpeedKMH: 900,
                progress: .completed(arrival: .observedGround(
                    firstObservedAt: arrival,
                    confirmedAt: arrival,
                )),
                inferredEndpoints: [],
                supportedIntervals: [.init(start: departure, end: arrival, kind: .observedMotion)],
            )
            model.forecasts.setPlanning(PlanningSnapshot(stays: [], homeRegion: nil))
            model.setDataIssueScan(DataIssueScanResult(
                revision: UUID(uuidString: "00000000-0000-0000-0000-000000000803")!,
                issues: [],
                reviews: [],
                completedFlights: [flight],
                nextReassessmentAt: nil,
            ))
            return model
        }

        @MainActor
        static func flightYearReportModel(state: FlightReviewPreviewState) -> YearReportModel {
            let report = loadedYearReportModel()
            report.setDataIssueScan(flightScan(state: state))
            return report
        }

        @MainActor
        static func flightHistoryYearReportModel() -> YearReportModel {
            let report = loadedYearReportModel()
            let original = flightReview(state: .completed).flights[0]
            let earlierDate = report.calendar.startOfDay(for: original.startedAt)
                .addingTimeInterval(-10 * 24 * 3600 + 23 * 3600)
            let earlier = FlightAssessment(
                id: .init(
                    recordingSource: original.id.recordingSource,
                    departureSampleID: UUID(uuidString: "00000000-0000-0000-0000-000000000801")!,
                ),
                startedAt: earlierDate,
                lastObservationAt: earlierDate.addingTimeInterval(12 * 3600),
                lastFlightAt: earlierDate.addingTimeInterval(11 * 3600),
                airborneSampleIDs: [],
                groundSampleIDs: [],
                peakSpeedKMH: 900,
                progress: .completed(arrival: .observedGround(
                    firstObservedAt: earlierDate.addingTimeInterval(12 * 3600),
                    confirmedAt: earlierDate.addingTimeInterval(12 * 3600),
                )),
                inferredEndpoints: [],
                supportedIntervals: [.init(
                    start: earlierDate,
                    end: earlierDate.addingTimeInterval(11 * 3600),
                    kind: .observedMotion,
                )],
            )
            report.setDataIssueScan(DataIssueScanResult(
                revision: UUID(),
                issues: [],
                reviews: [],
                completedFlights: [earlier, original],
                nextReassessmentAt: nil,
            ))
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
                completedFlights: review.flights.filter { !$0.isPending },
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
                        sampleID: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
                        replacementRegions: [.newYork],
                    )],
                ), flight: nil),
            )
        }

        static func flightReview(state: FlightReviewPreviewState) -> GPSCorrectionReview {
            flightReview(state: state, date: referenceNow)
        }

        /// An unresolved morning flight and a later completed flight share one review.
        static func mixedFlightReview() -> GPSCorrectionReview {
            let ready = flightReview(state: .ready)
            guard let proposal = ready.proposal else {
                preconditionFailure("Ready fixture must include a correction proposal")
            }
            let points = [
                Coordinate(latitude: 37.6213, longitude: -122.3790),
                Coordinate(latitude: 39.53, longitude: -106.16),
                Coordinate(latitude: 41.2, longitude: -95.9),
            ].enumerated().map { index, coordinate in
                SampleCorrectionPoint(
                    sample: LocationSample(
                        id: UUID(uuidString: String(
                            format: "00000000-0000-0000-0000-%012d",
                            390 + index,
                        ))!,
                        timestamp: referenceNow
                            .addingTimeInterval((-11 + Double(index) * 1.5) * 3600),
                        coordinate: coordinate,
                        horizontalAccuracy: 30,
                        source: .gpsSignificantChange,
                        recordingDeviceID: CurrentRecordingDevice.preview.id,
                    ),
                    regions: index == 0 ? [.california] : [.other],
                )
            }
            let pending = FlightAssessment(
                id: .init(
                    recordingSource: .device(CurrentRecordingDevice.preview.id),
                    departureSampleID: points[0].sample.id,
                ),
                startedAt: points[0].sample.timestamp,
                lastObservationAt: points[2].sample.timestamp,
                lastFlightAt: points[2].sample.timestamp,
                airborneSampleIDs: [points[1].sample.id],
                groundSampleIDs: [],
                peakSpeedKMH: 1040,
                progress: .awaitingArrival,
                inferredEndpoints: [],
                supportedIntervals: [.init(
                    start: points[0].sample.timestamp,
                    end: points[2].sample.timestamp,
                    kind: .observedMotion,
                )],
            )
            return GPSCorrectionReview(
                id: ready.id,
                day: ready.day,
                points: points + ready.points,
                state: .ready(SampleCorrectionProposal(
                    kind: proposal.kind,
                    day: ready.day,
                    resultingRegions: proposal.resultingRegions.union(points.flatMap(\.regions)),
                    edits: proposal.edits,
                ), flight: ready.flight),
                flights: [pending] + ready.flights,
                pointCorrections: ready.pointCorrections,
            )
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
                case .ready, .completed, .uncertainArrival: [0, 1, 2, 3, 4]
            }
            let points = visibleIndices.map { index in
                let region: Region = switch index {
                    case 0: .california
                    case 4: .newYork
                    default: .other
                }
                return SampleCorrectionPoint(
                    sample: LocationSample(
                        id: UUID(uuidString: String(
                            format: "00000000-0000-0000-0000-%012d",
                            300 + index,
                        ))!,
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
                case .uncertainArrival: .completed(arrival: .uncertainTiming(
                        lastSupportedTravelAt: date.addingTimeInterval(-15 * 60),
                        firstObservedAt: date.addingTimeInterval(3 * 86400),
                        confirmedAt: date.addingTimeInterval(3 * 86400 + 600),
                    ))
                case .flightLikely: .flightLikely
                case .waiting, .stale: .awaitingArrival
                case .ready, .noPresence, .completed: .completed(arrival: .observedGround(
                        firstObservedAt: date,
                        confirmedAt: date,
                    ))
            }
            let flight = FlightAssessment(
                id: .init(
                    recordingSource: .device(CurrentRecordingDevice.preview.id),
                    departureSampleID: points[0].sample.id,
                ),
                startedAt: date.addingTimeInterval(-5 * 60 * 60),
                lastObservationAt: state == .uncertainArrival ? date
                    .addingTimeInterval(3 * 86400 + 600) : date
                    .addingTimeInterval(state == .stale ? -2 * 60 * 60 : 0),
                lastFlightAt: date.addingTimeInterval(-15 * 60),
                airborneSampleIDs: airborne,
                groundSampleIDs: Set(points.map(\.sample.id)).subtracting(airborne),
                peakSpeedKMH: 1040,
                progress: progress,
                inferredEndpoints: [],
                supportedIntervals: [.init(
                    start: date.addingTimeInterval(-5 * 60 * 60),
                    end: date.addingTimeInterval(-15 * 60),
                    kind: .observedMotion,
                )],
            )
            let reviewState: GPSCorrectionReview.State = switch state {
                case .flightLikely, .waiting, .stale:
                    .pending(flight)
                case .ready, .noPresence, .uncertainArrival:
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
            let pointCorrections: [FlightPointCorrection] = flight.isPending ? [] : points
                .filter { state != .uncertainArrival || airborne.contains($0.sample.id) }
                .map { point in
                    FlightPointCorrection(
                        sampleID: point.sample.id,
                        action: point.regions.isEmpty ? .restoreGPS : .includeInFlight,
                        day: day.day,
                        resultingRegions: Set(points.filter { $0.sample.id != point.sample.id }
                            .flatMap(\.regions))
                            .union(point.regions.isEmpty ? [.other] : []),
                    )
                }
            return GPSCorrectionReview(
                id: reviewID,
                day: day,
                points: points,
                state: reviewState,
                pointCorrections: pointCorrections,
            )
        }
    }
#endif
