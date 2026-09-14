import Foundation
import Testing
import WhereCore

private typealias Fixtures = FlightTrajectoryFixtures

struct FlightTrajectoryAnalyzerTests {
    private let analyzer = FlightTrajectoryAnalyzer()

    @Test(.disabled(
        if: ProcessInfo.processInfo.environment["WHERE_FLIGHT_VERIFICATION_CONFIG"] == nil,
        "Supply a local flight-verification configuration to replay an external backup.",
    ))
    func productionArchiveReplayOnRequest() throws {
        let path = try #require(ProcessInfo.processInfo
            .environment["WHERE_FLIGHT_VERIFICATION_CONFIG"])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let configuration = try decoder.decode(
            FlightArchiveVerificationConfiguration.self,
            from: Data(contentsOf: URL(fileURLWithPath: path)),
        )
        let archive = try BackupService().readArchive(
            at: URL(fileURLWithPath: configuration.backupPath),
        ).archive
        let samples = RecordingDeviceRemovalFilter.visibleSamples(
            archive.samples,
            removals: archive.recordingDeviceRemovals,
        ).filter { $0.timestamp >= configuration.from && $0.timestamp < configuration.until }
        #expect(samples.count == configuration.expectedInputSampleCount)
        let assessments = analyzer.analyze(samples: samples, now: configuration.now)
        try #require(assessments.count == 1)
        let flight = assessments[0]
        #expect(flight.progress == .completed(arrivedAt: configuration.expectedArrivalAt))
        #expect(flight.lastObservationAt == configuration.expectedArrivalConfirmedAt)
        #expect(configuration.expectedAirborneSampleIDs.isSubset(of: flight.airborneSampleIDs))
        #expect(configuration.expectedPreservedSampleIDs.isDisjoint(with: flight.airborneSampleIDs))
        let cruise = try #require(analyzer.analyze(
            samples: samples,
            now: configuration.cruiseCheckAt,
        ).first)
        #expect(cruise.progress == .flightLikely)
        let awaiting = try #require(analyzer.analyze(
            samples: samples,
            now: configuration.awaitingArrivalCheckAt,
        ).first)
        #expect(awaiting.progress == .awaitingArrival)
    }

    @Test func recognizesTheSyntheticCruiseAndTurningApproachAfterDwell() throws {
        let trace = Fixtures.turningFlight()
        let assessments = analyzer.analyze(samples: trace.samples, now: trace.readyAt)
        let flight = try #require(assessments.first)
        #expect(assessments.count == 1)
        #expect(flight.progress == .completed(arrivedAt: trace.firstGroundAt))
        #expect(flight.peakSpeedKMH > 850)
        #expect(flight.airborneSampleIDs.contains(trace.shortIntervalID))
        #expect(flight.airborneSampleIDs.contains(Fixtures.sampleID(13)))
        #expect(flight.airborneSampleIDs.contains(Fixtures.sampleID(14)))
        #expect(flight.airborneSampleIDs.contains(trace.departureNoiseID) == false)
        #expect(flight.airborneSampleIDs.contains(Fixtures.sampleID(15)) == false)
        #expect(flight.groundSampleIDs.contains(Fixtures.sampleID(15)))
        #expect(flight.groundSampleIDs.contains(Fixtures.sampleID(17)))
        #expect(flight.airborneSampleIDs.isDisjoint(with: flight.groundSampleIDs))
    }

    @Test func prefixesRequireCruiseEvidenceAndThenObservedArrival() throws {
        let trace = Fixtures.turningFlight()
        #expect(analyzer.analyze(samples: trace.samples, now: Fixtures.date(minutes: 20)).isEmpty)
        let cruise = try #require(analyzer.analyze(
            samples: trace.samples,
            now: Fixtures.date(minutes: 25),
        ).first)
        #expect(cruise.progress == .flightLikely)
        let approach = try #require(analyzer.analyze(
            samples: trace.samples,
            now: Fixtures.date(minutes: 125),
        ).first)
        #expect(approach.progress == .awaitingArrival)
        let taxi = try #require(analyzer.analyze(
            samples: trace.samples,
            now: Fixtures.date(minutes: 135),
        ).first)
        #expect(taxi.progress == .awaitingArrival)
        #expect(taxi.groundSampleIDs.contains(Fixtures.sampleID(15)) == false)
        #expect(cruise.id == taxi.id)
    }

    @Test func silenceChangesFreshnessWithoutInventingArrival() throws {
        let trace = Fixtures.turningFlight()
        let prefix = trace.samples.filter { $0.timestamp <= trace.lastCruiseAt }
        let justBefore = try #require(analyzer.analyze(
            samples: prefix,
            now: trace.lastCruiseAt.addingTimeInterval(1799),
        ).first)
        #expect(justBefore.progress == .flightLikely)
        let stale = try #require(analyzer.analyze(
            samples: prefix,
            now: trace.lastCruiseAt.addingTimeInterval(1800),
        ).first)
        #expect(stale.progress == .awaitingArrival)
        #expect(stale.nextReassessmentAt == nil)
        let muchLater = try #require(analyzer.analyze(
            samples: prefix,
            now: trace.lastCruiseAt.addingTimeInterval(86400),
        ).first)
        #expect(muchLater.progress == .awaitingArrival)
        #expect(muchLater.id == stale.id)
    }

    @Test func duplicateCallbacksKeepEveryReviewedSampleIdentity() throws {
        let trace = Fixtures.turningFlight()
        let duplicate = Fixtures.sample(99, minutes: 25, east: 120, source: .gpsVisit)
        let flight = try #require(analyzer.analyze(
            samples: trace.samples + [duplicate],
            now: trace.readyAt,
        ).first)
        #expect(flight.airborneSampleIDs.contains(duplicate.id))
        #expect(flight.airborneSampleIDs.contains(Fixtures.sampleID(7)))
        #expect(flight.airborneSampleIDs.contains(trace.shortIntervalID))
    }

    @Test func nearSimultaneousDepartureDuplicatesRemainEndpoints() throws {
        let trace = Fixtures.turningFlight()
        let duplicate = Fixtures.sample(99, minutes: 15 + 0.5 / 60, east: 5, source: .gpsVisit)
        let flight = try #require(analyzer.analyze(
            samples: trace.samples + [duplicate],
            now: trace.readyAt,
        ).first)
        #expect(flight.airborneSampleIDs.contains(duplicate.id) == false)
        #expect(flight.airborneSampleIDs.contains(Fixtures.sampleID(5)) == false)
    }

    @Test func denseCruiseCallbacksDoNotPrematurelyReportAwaitingArrival() throws {
        let trace = Fixtures.turningFlight()
        let flight = try #require(analyzer.analyze(
            samples: trace.samples,
            now: Fixtures.date(minutes: 25 + 5.0 / 60),
        ).first)
        #expect(flight.progress == .flightLikely)
        #expect(flight.lastFlightAt == Fixtures.date(minutes: 25 + 5.0 / 60))
    }

    @Test func aContradictoryTrailingFixDoesNotExtendFreshCruiseEvidence() throws {
        let trace = Fixtures.turningFlight()
        let prefix = trace.samples.filter { $0.timestamp <= Fixtures.date(minutes: 25) }
        // Plausible against the older five-minute baseline, but impossible
        // against the preceding anchor only five seconds before this fix.
        let teleport = Fixtures.sample(99, minutes: 25 + 5.0 / 60, east: 150)
        let flight = try #require(analyzer.analyze(
            samples: prefix + [teleport],
            now: teleport.timestamp,
        ).first)
        #expect(flight.progress == .awaitingArrival)
        #expect(flight.lastFlightAt == Fixtures.date(minutes: 25))
        #expect(flight.airborneSampleIDs.contains(teleport.id) == false)
    }

    @Test(arguments: [15, 30, 60, 300])
    func samplingDensityDoesNotTurnCruiseIntoGround(cadenceSeconds: Int) throws {
        var samples = [
            Fixtures.sample(1, minutes: 0, east: 0),
            Fixtures.sample(2, minutes: 5, east: 0),
            Fixtures.sample(3, minutes: 10, east: 0),
        ]
        for seconds in stride(from: 0, through: 1200, by: cadenceSeconds) {
            samples.append(Fixtures.sample(
                100 + seconds,
                minutes: 15 + Double(seconds) / 60,
                east: Double(seconds) * 0.25,
            ))
        }
        samples += [
            Fixtures.sample(2001, minutes: 40, east: 300),
            Fixtures.sample(2002, minutes: 45, east: 300),
        ]
        let flight = try #require(analyzer.analyze(
            samples: samples,
            now: Fixtures.date(minutes: 45),
        ).first)
        #expect(flight.startedAt == Fixtures.date(minutes: 15))
        #expect(flight.progress == .completed(arrivedAt: Fixtures.date(minutes: 35)))
        #expect(flight.airborneSampleIDs.isEmpty == false)
    }

    @Test func separateDevicesAndLegacyHistoryCannotManufactureMovement() {
        let second = RecordingDeviceID(rawValue: Fixtures.sampleID(9001))
        var samples: [LocationSample] = []
        for index in 0 ..< 6 {
            samples.append(Fixtures.sample(index + 1, minutes: Double(index) * 5, east: 0))
            samples.append(Fixtures.sample(
                index + 101,
                minutes: Double(index) * 5 + 1,
                east: 40,
                deviceID: second,
            ))
            samples.append(Fixtures.sample(
                index + 201,
                minutes: Double(index) * 5 + 2,
                east: 80,
                deviceID: nil,
            ))
        }
        #expect(analyzer.analyze(samples: samples, now: Fixtures.date(minutes: 60)).isEmpty)
    }

    @Test func anotherDeviceCannotLandTheFlyingDevice() throws {
        let trace = Fixtures.turningFlight()
        let prefix = trace.samples.filter { $0.timestamp <= trace.lastCruiseAt }
        let second = RecordingDeviceID(rawValue: Fixtures.sampleID(9001))
        let ground = (0 ..< 4).map { index in
            Fixtures.sample(
                index + 101,
                minutes: 130 + Double(index) * 5,
                east: 1470,
                deviceID: second,
            )
        }
        let flight = try #require(analyzer.analyze(
            samples: prefix + ground,
            now: Fixtures.date(minutes: 145),
        ).first)
        #expect(flight.id.recordingDeviceID == Fixtures.device)
        #expect(flight.progress == .awaitingArrival)
        #expect(flight.groundSampleIDs.isDisjoint(with: Set(ground.map(\.id))))
    }

    @Test func poorAndConflictingShortIntervalFixesStayUncorrected() throws {
        let trace = Fixtures.turningFlight()
        let poor = Fixtures.sample(101, minutes: 26, east: 150, accuracy: 2000)
        let conflicting = Fixtures.sample(102, minutes: 25 + 0.5 / 60, east: 300)
        let flight = try #require(analyzer.analyze(
            samples: trace.samples + [poor, conflicting],
            now: trace.readyAt,
        ).first)
        #expect(flight.airborneSampleIDs.contains(poor.id) == false)
        #expect(flight.airborneSampleIDs.contains(conflicting.id) == false)
        #expect(flight.progress == .completed(arrivedAt: trace.firstGroundAt))
    }

    @Test func teleportReversalsAndImpossibleSpeedsDoNotConfirmAFlight() {
        let reversal = [
            Fixtures.sample(1, minutes: 0, east: 0),
            Fixtures.sample(2, minutes: 5, east: 75),
            Fixtures.sample(3, minutes: 10, east: 0),
        ]
        let impossible = [
            Fixtures.sample(1, minutes: 0, east: 0),
            Fixtures.sample(2, minutes: 5, east: 200),
            Fixtures.sample(3, minutes: 10, east: 400),
        ]
        #expect(analyzer.analyze(samples: reversal, now: Fixtures.date(minutes: 20)).isEmpty)
        #expect(analyzer.analyze(samples: impossible, now: Fixtures.date(minutes: 20)).isEmpty)
    }

    @Test func motionBelowTheJetThresholdRemainsUncertain() {
        let samples = [
            Fixtures.sample(1, minutes: 0, east: 0),
            Fixtures.sample(2, minutes: 5, east: 30),
            Fixtures.sample(3, minutes: 10, east: 60),
            Fixtures.sample(4, minutes: 15, east: 90),
        ]
        #expect(analyzer.analyze(samples: samples, now: Fixtures.date(minutes: 20)).isEmpty)
    }

    @Test func motionSensorsCanVetoDwellButAltitudeDoesNotCreateFlight() throws {
        let trace = Fixtures.turningFlight()
        let flyingSpeed = LocationMotion(
            speed: .init(metersPerSecond: 200, accuracyMetersPerSecond: 2),
            altitude: .init(meters: 9000, accuracyMeters: 10),
        )
        let contradicted = trace.samples.map { sample in
            sample.timestamp >= trace.firstGroundAt
                ? Fixtures.replacing(sample, motion: flyingSpeed) : sample
        }
        let flight = try #require(analyzer.analyze(
            samples: contradicted,
            now: Fixtures.date(minutes: 170),
        ).first)
        #expect(flight.progress == .awaitingArrival)
        let highGround = (0 ..< 4).map { index in
            Fixtures.sample(
                index + 101,
                minutes: Double(index) * 5,
                east: 0,
                motion: .init(speed: nil, altitude: .init(meters: 5000, accuracyMeters: 10)),
            )
        }
        #expect(analyzer.analyze(samples: highGround, now: Fixtures.date(minutes: 20)).isEmpty)
    }

    @Test func denseContradictoryObservationsPreventArrivalConfirmation() throws {
        let trace = Fixtures.turningFlight()
        let highSpeed = Fixtures.sample(
            101,
            minutes: 135 + 20.0 / 60,
            east: 1445,
            north: 8,
            motion: .init(
                speed: .init(metersPerSecond: 200, accuracyMetersPerSecond: 1),
                altitude: nil,
            ),
        )
        let teleport = Fixtures.sample(102, minutes: 135 + 30.0 / 60, east: 1800)
        for contradiction in [highSpeed, teleport] {
            let flight = try #require(analyzer.analyze(
                samples: trace.samples + [contradiction],
                now: trace.readyAt,
            ).first)
            #expect(flight.progress == .awaitingArrival)
            #expect(flight.groundSampleIDs.contains(contradiction.id) == false)
            #expect(flight.airborneSampleIDs.contains(contradiction.id) == false)
        }
    }

    @Test func midnightAndInputOrderingDoNotSplitAFlight() throws {
        let trace = Fixtures.turningFlight()
        let offset: TimeInterval = 23 * 3600
        let shifted = trace.samples.map {
            Fixtures.replacing($0, timestamp: $0.timestamp.addingTimeInterval(offset))
        }
        let expected = analyzer.analyze(
            samples: shifted,
            now: trace.readyAt.addingTimeInterval(offset),
        )
        let reversed = analyzer.analyze(
            samples: Array(shifted.reversed()),
            now: trace.readyAt.addingTimeInterval(offset),
        )
        let flight = try #require(expected.first)
        #expect(expected.count == 1)
        #expect(flight
            .progress == .completed(arrivedAt: trace.firstGroundAt.addingTimeInterval(offset)))
        #expect(reversed == expected)
    }

    @Test func completedObservationDoesNotFollowLaterUnrelatedLocations() throws {
        let trace = Fixtures.turningFlight()
        let later = Fixtures.sample(999, minutes: 24 * 60, east: 1500)
        let flight = try #require(analyzer.analyze(
            samples: trace.samples + [later],
            now: later.timestamp,
        ).first)
        #expect(flight.progress == .completed(arrivedAt: trace.firstGroundAt))
        #expect(flight.lastObservationAt == trace.readyAt)
    }

    @Test func aRealLayoverSeparatesFlightsAndProtectsGroundSamples() throws {
        let samples = [
            Fixtures.sample(1, minutes: 0, east: 0),
            Fixtures.sample(2, minutes: 5, east: 75),
            Fixtures.sample(3, minutes: 10, east: 150),
            Fixtures.sample(4, minutes: 15, east: 150),
            Fixtures.sample(5, minutes: 20, east: 150),
            Fixtures.sample(6, minutes: 25, east: 150),
            Fixtures.sample(7, minutes: 30, east: 225),
            Fixtures.sample(8, minutes: 35, east: 300),
            Fixtures.sample(9, minutes: 40, east: 300),
            Fixtures.sample(10, minutes: 45, east: 300),
        ]
        let flights = analyzer.analyze(samples: samples, now: Fixtures.date(minutes: 45))
        try #require(flights.count == 2)
        #expect(flights[0].progress == .completed(arrivedAt: Fixtures.date(minutes: 10)))
        #expect(flights[1].progress == .completed(arrivedAt: Fixtures.date(minutes: 35)))
        let layoverIDs = Set(samples[2 ... 5].map(\.id))
        #expect(flights.allSatisfy { $0.airborneSampleIDs.isDisjoint(with: layoverIDs) })
        #expect(flights[0].groundSampleIDs.contains(Fixtures.sampleID(4)))
    }

    @Test func layoverConfirmationCanShareTheNextDepartureAnchor() throws {
        let samples = [
            Fixtures.sample(1, minutes: 0, east: 0),
            Fixtures.sample(2, minutes: 5, east: 75),
            Fixtures.sample(3, minutes: 10, east: 150),
            Fixtures.sample(4, minutes: 15, east: 150),
            // This third ground anchor confirms arrival and starts the next
            // flight's first cruise leg. Both flights must retain it as ground.
            Fixtures.sample(5, minutes: 20, east: 150),
            Fixtures.sample(6, minutes: 25, east: 225),
            Fixtures.sample(7, minutes: 30, east: 300),
            Fixtures.sample(8, minutes: 35, east: 300),
            Fixtures.sample(9, minutes: 40, east: 300),
        ]
        let flights = analyzer.analyze(samples: samples, now: Fixtures.date(minutes: 40))
        try #require(flights.count == 2)
        #expect(flights[0].progress == .completed(arrivedAt: Fixtures.date(minutes: 10)))
        #expect(flights[0].lastObservationAt == Fixtures.date(minutes: 20))
        #expect(flights[1].progress == .completed(arrivedAt: Fixtures.date(minutes: 30)))
        #expect(flights[1].id.departureSampleID == Fixtures.sampleID(5))
        let layoverIDs = Set(samples[2 ... 4].map(\.id))
        #expect(flights.allSatisfy { $0.airborneSampleIDs.isDisjoint(with: layoverIDs) })
        #expect(flights.allSatisfy { layoverIDs.isSubset(of: $0.groundSampleIDs) })
    }

    @Test func aLongUnknownGapCannotBecomeAMotionBaseline() {
        let samples = [
            Fixtures.sample(1, minutes: 0, east: 0),
            Fixtures.sample(2, minutes: 125, east: 1875),
            Fixtures.sample(3, minutes: 250, east: 3750),
        ]
        #expect(analyzer.analyze(samples: samples, now: Fixtures.date(minutes: 250)).isEmpty)
    }

    @Test func approachExtensionStopsAtItsTimeBound() throws {
        var samples = [
            Fixtures.sample(1, minutes: 0, east: 0),
            Fixtures.sample(2, minutes: 5, east: 75),
            Fixtures.sample(3, minutes: 10, east: 150),
        ]
        for index in 1 ... 7 {
            samples.append(Fixtures.sample(
                index + 3,
                minutes: 10 + Double(index) * 5,
                east: 150 + Double(index) * 20,
            ))
        }
        samples += [
            Fixtures.sample(11, minutes: 50, east: 290),
            Fixtures.sample(12, minutes: 55, east: 290),
        ]
        let flight = try #require(analyzer.analyze(
            samples: samples,
            now: Fixtures.date(minutes: 55),
        ).first)
        #expect(flight.progress == .completed(arrivedAt: Fixtures.date(minutes: 45)))
        #expect(flight.airborneSampleIDs.contains(Fixtures.sampleID(8)))
        #expect(flight.airborneSampleIDs.contains(Fixtures.sampleID(9)) == false)
        #expect(flight.airborneSampleIDs.contains(Fixtures.sampleID(10)) == false)
    }

    @Test func shortBurstsAndUncertainThresholdSpeedsDoNotConfirmFlight() {
        let brief = [
            Fixtures.sample(1, minutes: 0, east: 0),
            Fixtures.sample(2, minutes: 1, east: 15),
            Fixtures.sample(3, minutes: 2, east: 30),
        ]
        let uncertain = [
            Fixtures.sample(1, minutes: 0, east: 0, accuracy: 250),
            Fixtures.sample(2, minutes: 5, east: 37.6, accuracy: 250),
            Fixtures.sample(3, minutes: 10, east: 75.2, accuracy: 250),
        ]
        #expect(analyzer.analyze(samples: brief, now: Fixtures.date(minutes: 10)).isEmpty)
        #expect(analyzer.analyze(samples: uncertain, now: Fixtures.date(minutes: 10)).isEmpty)
    }

    @Test func manualAndEvidenceCoordinatesNeverBecomeFlightEvidence() {
        let samples = [
            Fixtures.sample(1, minutes: 0, east: 0, source: .manual),
            Fixtures.sample(2, minutes: 5, east: 75, source: .manual),
            Fixtures.sample(3, minutes: 10, east: 150, source: .evidenceImplied(
                id: Fixtures.sampleID(999),
                kind: .boardingPass,
            )),
        ]
        #expect(analyzer.analyze(samples: samples, now: Fixtures.date(minutes: 20)).isEmpty)
    }
}
