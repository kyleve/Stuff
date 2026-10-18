import Foundation
import RegionKit
import Testing
import WhereCore

struct FlightFixtureExporterTests {
    private typealias Fixtures = FlightTrajectoryFixtures
    private let replacementStart = Date(timeIntervalSince1970: 1_577_836_800)
    private let replacementOrigin = Coordinate(latitude: 15, longitude: -30)

    @Test func retainsOrderDuplicatesConflictsDevicesAndSensorAvailability() throws {
        let motion = LocationMotion(
            speed: .init(metersPerSecond: 220, accuracyMetersPerSecond: 5),
            altitude: .init(meters: 10000, accuracyMeters: 20),
        )
        let input = [
            Fixtures.sample(94, minutes: 60, east: 700, deviceID: nil),
            Fixtures.sample(
                92,
                minutes: 5,
                east: 0,
                accuracy: 800,
                source: .gpsVisit,
                motion: motion,
            ),
            Fixtures.sample(91, minutes: -1, east: 0),
            Fixtures.sample(
                92,
                minutes: 5,
                east: 0,
                accuracy: 800,
                source: .gpsVisit,
                motion: motion,
            ),
            Fixtures.sample(92, minutes: 5, east: 20, motion: .init(speed: nil, altitude: nil)),
            Fixtures.sample(
                93,
                minutes: 10,
                east: 100,
                deviceID: RecordingDeviceID(rawValue: Fixtures.sampleID(9001)),
            ),
            Fixtures.sample(95, minutes: 5, east: 0, source: .manual),
            Fixtures.sample(96, minutes: 70, east: 900),
        ]
        let exported = try FlightFixtureExporter(
            samples: input,
            from: Fixtures.start,
            until: Fixtures.date(minutes: 70),
            now: Fixtures.date(minutes: 65),
            replacementStart: replacementStart,
            replacementOrigin: replacementOrigin,
        )
        #expect(exported.originalSamples == [input[0], input[1], input[3], input[4], input[5]])
        #expect(exported.samples.count == 5)
        for (original, replacement) in zip(exported.originalSamples, exported.samples) {
            #expect(replacement.id != original.id)
            #expect(replacement.id == exported.sampleIDs[original.id])
            #expect(replacement.timestamp == exported.shifted(original.timestamp))
            #expect(replacement.horizontalAccuracy == original.horizontalAccuracy)
            #expect(replacement.source == original.source)
            #expect(replacement.motion == original.motion)
        }
        #expect(exported.samples[0].recordingDeviceID == nil)
        #expect(exported.samples[1] == exported.samples[2])
        #expect(exported.samples[1].id == exported.samples[3].id)
        #expect(exported.samples[1].coordinate != exported.samples[3].coordinate)
        #expect(exported.samples[1].recordingDeviceID != exported.samples[4].recordingDeviceID)
        #expect(exported.now == replacementStart.addingTimeInterval(65 * 60))
        let source = try exported.swiftSource(typeName: "RecordedFlightFixture")
        #expect(source.contains("enum RecordedFlightFixture"))
        #expect(source.contains("LocationMotion(speed: nil, altitude: nil)"))
        #expect(!source.contains(Fixtures.device.rawValue.uuidString))
        #expect(try exported.swiftSource(typeName: "RecordedFlightFixture") == source)
        for invalidName in ["Injected {}", "Any", "Self"] {
            #expect(throws: FlightFixtureExporter.ExportError.self) {
                try exported.swiftSource(typeName: invalidName)
            }
        }
    }

    @Test func rotationPreservesDistancesAcrossTheDateLineAndNearPoles() throws {
        let coordinates = [
            Coordinate(latitude: 89.9, longitude: 179.9),
            Coordinate(latitude: 88.5, longitude: -179.9),
            Coordinate(latitude: 65, longitude: 170),
            Coordinate(latitude: 65, longitude: -160),
            Coordinate(latitude: -80, longitude: -130),
        ]
        let samples = coordinates.enumerated().map { index, coordinate in
            LocationSample(
                id: Fixtures.sampleID(index + 1),
                timestamp: Fixtures.date(minutes: Double(index)),
                coordinate: coordinate,
                horizontalAccuracy: 5,
                source: .gpsSignificantChange,
                recordingDeviceID: Fixtures.device,
                motion: nil,
            )
        }
        let exported = try FlightFixtureExporter(
            samples: samples,
            from: Fixtures.start,
            until: Fixtures.date(minutes: 5),
            now: Fixtures.date(minutes: 6),
            replacementStart: replacementStart,
            replacementOrigin: replacementOrigin,
        )
        #expect(exported.samples[0].coordinate.distance(to: replacementOrigin) < 0.001)
        for i in samples.indices {
            for j in samples.indices {
                let before = samples[i].coordinate.distance(to: samples[j].coordinate)
                let after = exported.samples[i].coordinate
                    .distance(to: exported.samples[j].coordinate)
                #expect(abs(before - after) < 0.001)
            }
        }
    }

    @Test(arguments: FlightTrajectoryGenerator.Profile.allCases)
    func transformationPreservesGeneratedFlightEvidence(profile: FlightTrajectoryGenerator
        .Profile) throws
    {
        let scenario = FlightTrajectoryGenerator.make(profile: profile, seed: 42)
        let exported = try FlightFixtureExporter(
            samples: scenario.samples,
            from: Fixtures.start,
            until: scenario.now.addingTimeInterval(1),
            now: scenario.now,
            replacementStart: replacementStart,
            replacementOrigin: replacementOrigin,
        )
        try verifyAssessmentParity(exported, originalNow: scenario.now)
    }

    @Test func refusesEmptyWindowsAndInvalidCoordinates() {
        #expect(throws: FlightFixtureExporter.ExportError.self) {
            try FlightFixtureExporter(
                samples: [],
                from: Fixtures.start,
                until: Fixtures.date(minutes: 60),
                now: Fixtures.date(minutes: 60),
                replacementStart: replacementStart,
                replacementOrigin: replacementOrigin,
            )
        }
        #expect(throws: FlightFixtureExporter.ExportError.self) {
            try FlightFixtureExporter(
                samples: Fixtures.sparseFlight(),
                from: Fixtures.start,
                until: Fixtures.start,
                now: Fixtures.start,
                replacementStart: replacementStart,
                replacementOrigin: replacementOrigin,
            )
        }
        #expect(throws: FlightFixtureExporter.ExportError.self) {
            try FlightFixtureExporter(
                samples: Fixtures.sparseFlight(),
                from: Fixtures.start,
                until: Fixtures.date(minutes: 300),
                now: Fixtures.date(minutes: 300),
                replacementStart: replacementStart,
                replacementOrigin: Coordinate(latitude: 91, longitude: 0),
            )
        }
    }

    @Test(.disabled(
        if: ProcessInfo.processInfo.environment["WHERE_FLIGHT_FIXTURE_EXPORT_CONFIG"] == nil,
        "Supply a local export configuration to extract a recorded GPS fixture.",
    ))
    func exportArchiveFixtureOnRequest() throws {
        let path = try #require(ProcessInfo.processInfo
            .environment["WHERE_FLIGHT_FIXTURE_EXPORT_CONFIG"])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let configuration = try decoder.decode(
            FlightFixtureExporter.Configuration.self,
            from: Data(contentsOf: URL(fileURLWithPath: path)),
        )
        let archive = try BackupService()
            .readArchive(at: URL(fileURLWithPath: configuration.backupPath)).archive
        let exported = try FlightFixtureExporter(
            samples: RecordingDeviceRemovalFilter.visibleSamples(
                archive.samples,
                removals: archive.recordingDeviceRemovals,
            ),
            from: configuration.from,
            until: configuration.until,
            now: configuration.now,
            replacementStart: configuration.replacementStart,
            replacementOrigin: configuration.replacementOrigin,
        )
        try verifyAssessmentParity(exported, originalNow: configuration.now)
        let source = try exported.swiftSource(typeName: configuration.typeName)
        try Data(source.utf8).write(
            to: URL(fileURLWithPath: configuration.outputPath),
            options: .withoutOverwriting,
        )
        print(
            "Exported \(exported.samples.count) GPS callbacks after flight-evidence parity checks. Add independent expectations before committing the fixture.",
        )
    }

    /// Export must not silently alter recognition or correction authority. Numeric
    /// speed differences from spherical arithmetic have a 0.000001 km/h tolerance.
    private func verifyAssessmentParity(
        _ exported: FlightFixtureExporter,
        originalNow: Date,
    ) throws {
        let analyzer = FlightTrajectoryAnalyzer()
        let original = analyzer.analyze(samples: exported.originalSamples, now: originalNow)
        let replacement = analyzer.analyze(samples: exported.samples, now: exported.now)
        try #require(original.count == replacement.count)
        for (before, after) in zip(original, replacement) {
            try #require(after.id.departureSampleID == exported
                .sampleIDs[before.id.departureSampleID])
            switch before.id.recordingSource {
                case let .device(device):
                    try #require(try after.id
                        .recordingSource == .device(#require(exported.deviceIDs[device])))
                case .legacy: try #require(after.id.recordingSource == .legacy)
            }
            try #require(after.startedAt == exported.shifted(before.startedAt))
            try #require(after.lastObservationAt == exported.shifted(before.lastObservationAt))
            try #require(after.lastFlightAt == exported.shifted(before.lastFlightAt))
            let airborne = try Set(before.airborneSampleIDs
                .map { try #require(exported.sampleIDs[$0]) })
            let ground = try Set(before.groundSampleIDs
                .map { try #require(exported.sampleIDs[$0]) })
            try #require(after.airborneSampleIDs == airborne)
            try #require(after.groundSampleIDs == ground)
            try #require(abs(after.peakSpeedKMH - before.peakSpeedKMH) < 0.000001)
            let progress: FlightAssessment.Progress = switch before.progress {
                case .flightLikely: .flightLikely
                case .awaitingArrival: .awaitingArrival
                case let .completed(arrival):
                    switch arrival {
                        case let .observedGround(first, confirmed):
                            .completed(arrival: .observedGround(
                                firstObservedAt: exported.shifted(first),
                                confirmedAt: exported.shifted(confirmed),
                            ))
                        case let .uncertainTiming(last, first, confirmed):
                            .completed(arrival: .uncertainTiming(
                                lastSupportedTravelAt: exported.shifted(last),
                                firstObservedAt: exported.shifted(first),
                                confirmedAt: exported.shifted(confirmed),
                            ))
                    }
            }
            try #require(after.progress == progress)
            try #require(after.supportedIntervals == before.supportedIntervals.map {
                FlightAssessment.TravelInterval(
                    start: exported.shifted($0.start),
                    end: exported.shifted($0.end),
                    kind: $0.kind,
                )
            })
            try #require(before.inferredEndpoints.count == after.inferredEndpoints.count)
            for (beforeEndpoint, afterEndpoint) in zip(
                before.inferredEndpoints,
                after.inferredEndpoints,
            ) {
                try #require(afterEndpoint.sampleID == exported.sampleIDs[beforeEndpoint.sampleID])
                switch (beforeEndpoint.reason, afterEndpoint.reason) {
                    case let (
                    .recordingGap(beforeDuration, beforeSpeed),
                    .recordingGap(afterDuration, afterSpeed)
                ):
                        try #require(abs(beforeDuration - afterDuration) < 0.000001)
                        try #require(abs(beforeSpeed - afterSpeed) < 0.000001)
                    case let (.recordedSpeed(beforeSpeed), .recordedSpeed(afterSpeed)):
                        try #require(beforeSpeed == afterSpeed)
                    case (.recordingGap, .recordedSpeed), (.recordedSpeed, .recordingGap):
                        try #require(
                            Bool(false),
                            "Endpoint evidence changed during fixture transformation",
                        )
                }
            }
        }
    }
}
