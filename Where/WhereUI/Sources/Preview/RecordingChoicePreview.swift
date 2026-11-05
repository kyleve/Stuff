#if DEBUG
    import Foundation
    import RegionKit
    import WhereCore

    /// Synchronous rendering inputs for the shared review sections. Core-backed interaction
    /// tests separately verify how admitted inspections produce these presentation values.
    enum RecordingChoicePreview {
        enum State { case conflict, selected, unknownDates, unknownGeography }

        static func comparison(_ state: State) -> RecordingChoicePresentation.Comparison {
            let first =
                RecordingDeviceID(
                    rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                )
            let second =
                RecordingDeviceID(
                    rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                )
            let day = CalendarDay(year: 2026, month: 7, day: 15)
            let start = Date(timeIntervalSince1970: 1_784_102_400)
            let period = try! RecordingPeriod(start: start, end: start.addingTimeInterval(3600))
            let coverage = try! [
                RecordingPeriod(start: start, end: start.addingTimeInterval(601)),
                RecordingPeriod(
                    start: start.addingTimeInterval(2400),
                    end: start.addingTimeInterval(3001),
                ),
            ]
            let gaps = try! [
                RecordingPeriod(start: coverage[0].end, end: coverage[1].start),
                RecordingPeriod(start: coverage[1].end, end: period.end),
            ]
            let tracks = [first, second].map { deviceID in
                let region: Region = deviceID == first ? .california : .newYork
                let observations = [0.0, 600, 2400, 3000].map { seconds in
                    let timestamp = start.addingTimeInterval(seconds)
                    let context: RecordingDayAssignment = state == .unknownDates ? .unresolved :
                        .resolved(try! .init(
                            observedAt: timestamp,
                            timeZone: .gmt,
                        ))
                    let sample = LocationSample(
                        id: UUID(),
                        timestamp: timestamp,
                        coordinate: deviceID == first
                            ? Coordinate(latitude: 37.78, longitude: -122.42 + seconds / 100_000)
                            : Coordinate(latitude: 40.71, longitude: -74 + seconds / 100_000),
                        horizontalAccuracy: 10,
                        source: .gpsSignificantChange,
                        recordingDeviceID: deviceID,
                        recordingDay: context,
                    )
                    return try! RecordingObservation(
                        sample: sample,
                        recordingDay: context,
                        region: state == .unknownGeography ? nil : region,
                    )
                }
                return RecordingChoicePresentation.Track(
                    id: deviceID,
                    name: deviceID == first ? "iPhone Pro Max" : "iPhone Duo",
                    map: RecordedMapData(
                        points: observations.map { RecordedMapPoint(
                            coordinate: $0.sample.coordinate,
                            horizontalAccuracy: $0.sample.horizontalAccuracy,
                            attribution: state == .unknownGeography ? .unknown : .region(region),
                        ) },
                        routes: coverage.map { period in
                            .init(
                                id: .coverage(deviceID: deviceID, period: period),
                                coordinates: observations
                                    .filter { period.contains($0.sample.timestamp) }
                                    .map(\.sample.coordinate),
                            )
                        },
                    ),
                    observations: observations,
                    gaps: gaps,
                    days: state == .unknownDates ? .unassigned(known: []) : .known([day]),
                )
            }
            let policy = DataCompatibilityPolicy(
                current: RecordingEvidencePolicy.version,
                supportedMajors: [1],
            )
            let choice = try! HistoryDecision(
                id: .init(rawValue: UUID()),
                author: first,
                periods: [period],
                scope: .fixedPeriods,
                action: .select(first),
                predecessors: [],
                version: policy.current,
            )
            let controls = try! RecordingControlSnapshot(
                records: [RecordingControlCodec.encode(.source(choice), generationID: .initial)],
                generationID: .initial,
                policy: policy,
            )
            let selection = try! RecordingHistorySelection.resolve(
                observations: tracks.flatMap(\.observations),
                controls: controls,
                removals: [],
                within: period,
                version: policy.current,
            )
            let after: [DayPresence] = switch state {
                case .selected: [DayPresence(day: day, regions: [.california])]
                case .unknownGeography: [DayPresence(day: day, regions: [.other])]
                case .conflict, .unknownDates: []
            }
            return RecordingChoicePresentation.Comparison(
                tracks: tracks,
                before: [],
                after: after,
                explanations: [.init(period: period, text: WhereFormat.recordingSelection(
                    state == .unknownDates ? .unresolved(.recordingDay([first, second])) :
                        .unresolved(.competingTracks([
                            first,
                            second,
                        ])),
                    names: [:],
                ))],
                remainingIssues: try! RecordingIssue.grouped(
                    selection.issues,
                    version: policy.current,
                ).map { .init(
                    issue: $0,
                    names: Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0.name) }),
                ) },
            )
        }
    }
#endif
