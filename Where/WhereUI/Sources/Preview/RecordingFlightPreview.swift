#if DEBUG
    import Foundation
    @_spi(Testing) import WhereCore

    /// A synthetic half-hour flight with saved calendar context, assessed by the production
    /// selector.
    enum RecordingFlightPreview {
        enum Journey { case priorYear, dateLine }
        enum Failure: Error { case unexpectedAssessment }

        @MainActor
        static func reportModel(_ journey: Journey, year: Int) -> YearReportModel {
            do {
                let flight = try flight(journey)
                let first = CalendarDay(
                    year: year,
                    month: year == 2025 ? 12 : 1,
                    day: year == 2025 ? 28 : 1,
                )
                let last = CalendarDay(
                    year: year,
                    month: year == 2025 ? 12 : 1,
                    day: year == 2025 ? 31 : 3,
                )
                let days = first.days(through: last).map { day in
                    DayPresence(
                        day: day,
                        regions: year == 2025 && day < last ? [.california] : [.newYork],
                    )
                }
                let model = YearReportModel(
                    services: PreviewSupport.previewServices(),
                    details: YearReportDetails(
                        primaryRegions: [.california, .newYork],
                        report: YearReport(
                            year: year,
                            days: days,
                            totals: year == 2025 ? [.california: 3, .newYork: 1] : [.newYork: 3],
                            completeness: .recording(
                                version: RecordingEvidencePolicy.version,
                                days: CalendarDay.yearRange(year),
                                issues: [],
                            ),
                        ),
                        primaryRegionLocations: [:],
                    ),
                    selectedYear: year,
                    preferences: PreviewSupport.previewPreferences(),
                    now: { Date(timeIntervalSince1970: 1_767_441_600) },
                )
                model.forecasts.setPlanning(PlanningSnapshot(stays: [], homeRegion: nil))
                model.setDataIssueScan(DataIssueScanResult(
                    revision: UUID(uuidString: "00000000-0000-0000-0000-000000000902")!,
                    issues: [],
                    reviews: [],
                    completedFlights: [flight],
                    nextReassessmentAt: nil,
                ))
                return model
            } catch {
                preconditionFailure("Invalid recording flight preview: \(error)")
            }
        }

        static func flight(_ journey: Journey) throws -> FlightAssessment {
            // January 1, 2026, 10:00 UTC. UTC-12 records December 31; UTC+14 records January 2.
            let start = Date(timeIntervalSince1970: 1_767_261_600)
            let device =
                RecordingDeviceID(
                    rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000901")!,
                )
            let minutes: [Double] = [0, 5, 25, 30, 35]
            let observations = try minutes.enumerated().map { index, minute in
                let timestamp = start.addingTimeInterval(minute * 60)
                let offset: Int = switch journey {
                    case .priorYear: -12
                    case .dateLine: index < 2 ? -12 : 14
                }
                let assignment = try RecordingDayAssignment.resolved(.init(
                    observedAt: timestamp,
                    timeZone: TimeZone(secondsFromGMT: offset * 3600)!,
                ))
                let sample = LocationSample(
                    id: UUID(uuidString: String(
                        format: "00000000-0000-0000-0000-%012d",
                        910 + index,
                    ))!,
                    timestamp: timestamp,
                    coordinate: .init(latitude: 0, longitude: index < 2 ? 0 : 200 / 111.195),
                    horizontalAccuracy: 5,
                    source: .gpsSignificantChange,
                    recordingDeviceID: device,
                    recordingDay: assignment,
                )
                return try RecordingObservation(
                    sample: sample,
                    recordingDay: assignment,
                    region: nil,
                )
            }
            let selection = try RecordingHistorySelection.resolve(
                observations: observations,
                controls: RecordingControlSnapshot(
                    records: [],
                    generationID: .initial,
                    policy: DataCompatibilityPolicy(
                        current: RecordingEvidencePolicy.version,
                        supportedMajors: [1],
                    ),
                ),
                removals: [],
                within: RecordingPeriod(start: start, end: start.addingTimeInterval(36 * 60)),
                version: RecordingEvidencePolicy.version,
            )
            let samples = try selection.contributions.map { observation in
                guard let day = observation.recordingDay.day
                else { throw Failure.unexpectedAssessment }
                return AttributedLocationSample(
                    sample: observation.sample,
                    regions: observation.geography.presence,
                    day: .recording(day),
                )
            }
            let flights = FlightTrajectoryAnalyzer().analyze(
                history: LocationHistoryProjection(
                    samples: samples,
                    revisions: [],
                    contract: .recording(selection),
                ),
                now: start.addingTimeInterval(36 * 60),
            )
            guard flights.count == 1, let flight = flights.first, !flight.isPending else {
                throw Failure.unexpectedAssessment
            }
            return flight
        }
    }
#endif
