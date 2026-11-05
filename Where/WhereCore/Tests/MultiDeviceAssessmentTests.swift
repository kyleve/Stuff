import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct MultiDeviceAssessmentTests {
    @Test func finalSpatialAnchorDoesNotReplaceTheCurrentCorrectedGeography() throws {
        let first = try [0.0, 600, 1200].map {
            try RecordingAssessmentTestSupport.observation(
                seconds: $0,
                region: $0 == 1200 ? .newYork : .california,
            )
        }
        let second = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            longitude: -74,
            moving: false,
            region: .newYork,
        )
        let result = try MultiDeviceAssessment.assess(
            observations: first + second,
            within: RecordingAssessmentTestSupport.period(1200, 1201),
            places: [],
        )
        #expect(result.first?.selection == .agreement([
            RecordingAssessmentTestSupport.first,
            RecordingAssessmentTestSupport.second,
        ]))
    }

    @Test func anotherDevicesBoundaryDoesNotEraseTheFinalSpatialAnchor() throws {
        let first = try RecordingAssessmentTestSupport.track(moving: true)
        let second = try [0.5, 600.5, 1200.5].enumerated().map { index, seconds in
            try RecordingAssessmentTestSupport.observation(
                deviceID: RecordingAssessmentTestSupport.second,
                seconds: seconds,
                longitude: -74 + Double(index) * 0.02,
                region: .newYork,
            )
        }
        let result = try MultiDeviceAssessment.assess(
            observations: first + second,
            within: RecordingAssessmentTestSupport.period(1200.5, 1201),
            places: [],
        )
        #expect(result.first?.selection == .conflict([
            RecordingAssessmentTestSupport.first,
            RecordingAssessmentTestSupport.second,
        ]))
    }

    @Test func midnightBracketCannotHideKnownDaysOnSimultaneousObservations() throws {
        let observations = try RecordingHistorySelectionTestSupport.midnightObservations()
        let result = try MultiDeviceAssessment.assess(
            observations: observations,
            within: RecordingAssessmentTestSupport.period(0, 1),
            places: [],
        )
        #expect(result.count == 1)
        #expect(result.first?.selection == .conflict([
            RecordingAssessmentTestSupport.first,
            RecordingAssessmentTestSupport.second,
        ]))
    }

    @Test func finalPointSupportRetainsTheEstablishedCompetingTracks() throws {
        let first = try RecordingAssessmentTestSupport.track(moving: true)
        let second = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            longitude: -74,
            moving: true,
            region: .newYork,
        )
        let result = try MultiDeviceAssessment.assess(
            observations: first + second,
            within: RecordingAssessmentTestSupport.period(1200, 1201),
            places: [],
        )
        #expect(result.count == 1)
        #expect(result.first?.selection == .conflict([
            RecordingAssessmentTestSupport.first,
            RecordingAssessmentTestSupport.second,
        ]))
    }

    @Test func nearbyBoundaryPointsDoNotEstablishAGeographicConflict() throws {
        let nevada = try #require(Region(rawValue: "us-NV"))
        let oregon = try #require(Region(rawValue: "us-OR"))
        let first = try RecordingAssessmentTestSupport.track(moving: false, region: nevada)
        let second = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            longitude: -122.00001,
            moving: false,
            region: oregon,
        )
        #expect(try assess(first + second).allSatisfy { $0.selection == .uncertain([
            RecordingAssessmentTestSupport.first,
            RecordingAssessmentTestSupport.second,
        ]) })
    }

    @Test func isolatedDistantFixDoesNotEstablishAGeographicConflict() throws {
        let observed = try RecordingAssessmentTestSupport.track(moving: false)
        let isolated = try RecordingAssessmentTestSupport.observation(
            deviceID: RecordingAssessmentTestSupport.second,
            seconds: 600,
            longitude: -74,
            region: .newYork,
        )
        let result = try assess(observed + [isolated])
        #expect(result.contains { $0.tracks.count == 2 })
        #expect(result.allSatisfy { segment in
            switch segment.selection {
                case .conflict, .movingOverStationary: false
                case .noEvidence, .onlyAvailableDevice, .agreement, .uncertain: true
            }
        })
    }

    @Test func equalTimeSamplesCannotHideContradictoryAttribution() throws {
        let first = try RecordingAssessmentTestSupport.track(moving: false)
        let second = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            moving: false,
        )
        let contradictory = try RecordingAssessmentTestSupport.observation(
            seconds: 0,
            region: .newYork,
        )
        let result = try assess(first + second + [contradictory])
        let initial = try #require(result.first)
        #expect(initial.selection == .uncertain([
            RecordingAssessmentTestSupport.first,
            RecordingAssessmentTestSupport.second,
        ]))
        let track = try #require(initial.tracks.first {
            $0.deviceID == RecordingAssessmentTestSupport.first
        })
        #expect(track.region == nil)
        #expect(track.bracketingObservations.count(where: {
            $0.sample.timestamp == RecordingAssessmentTestSupport.time(0)
        }) == 2)
    }

    @Test func clippingAQueryDoesNotChangeEvidenceOrSelectionAtTheSameInstant() throws {
        let observations = try [-1800.0, -600, 0, 1200, 2400].map {
            try RecordingAssessmentTestSupport.observation(seconds: $0)
        }
        let full = try MultiDeviceAssessment.assess(
            observations: observations,
            within: RecordingAssessmentTestSupport.period(-1800, 2401),
            places: [],
        )
        let clipped = try MultiDeviceAssessment.assess(
            observations: observations,
            within: RecordingAssessmentTestSupport.period(600, 900),
            places: [],
        )
        let interval = try #require(clipped.first)
        let original = try #require(full.first { $0.period.contains(interval.period.start) })
        #expect(clipped.count == 1)
        #expect(interval.selection == original.selection)
        #expect(interval.tracks == original.tracks)
        #expect(try interval.period == RecordingAssessmentTestSupport.period(600, 900))
    }

    @Test func distinctNonPrimaryRegionsRemainDistinct() throws {
        let nevadaRegion = try #require(Region(rawValue: "us-NV"))
        let oregonRegion = try #require(Region(rawValue: "us-OR"))
        let nevada = try RecordingAssessmentTestSupport.track(
            longitude: -115,
            moving: true,
            region: nevadaRegion,
        )
        let oregon = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            longitude: -123,
            moving: true,
            region: oregonRegion,
        )
        let result = try assess(nevada + oregon)
        #expect(result.allSatisfy { $0.selection == .conflict([
            RecordingAssessmentTestSupport.first,
            RecordingAssessmentTestSupport.second,
        ]) })
        #expect(result.allSatisfy { Set($0.tracks.compactMap(\.region)) == [
            nevadaRegion,
            oregonRegion,
        ] })
    }

    private func assess(_ observations: [RecordingObservation]) throws
        -> [MultiDeviceAssessment.Segment]
    {
        try MultiDeviceAssessment.assess(
            observations: observations,
            within: RecordingAssessmentTestSupport.period(0, 1200),
            places: [],
        )
    }

    @Test func differentCoordinatesInTheSameRegionAndDayAgree() throws {
        let first = try RecordingAssessmentTestSupport.track(moving: true)
        let second = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            longitude: -121,
            moving: false,
        )
        let expected = MultiDeviceAssessment.Selection.agreement([
            RecordingAssessmentTestSupport.first,
            RecordingAssessmentTestSupport.second,
        ])
        #expect(try assess(first + second).allSatisfy { $0.selection == expected })
    }

    @Test func strongMovingEvidenceOutweighsStationaryEvidenceWithoutAVote() throws {
        let moving = try RecordingAssessmentTestSupport.track(moving: true)
        let stationary = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            longitude: -74,
            moving: false,
            region: .newYork,
        )
        let third = try RecordingAssessmentTestSupport.track(
            deviceID: .init(rawValue: UUID()),
            longitude: -74,
            moving: false,
            region: .newYork,
        )
        #expect(try assess(moving + stationary + third).allSatisfy {
            $0.selection == .movingOverStationary(RecordingAssessmentTestSupport.first)
        })
    }

    @Test func competingMovementRequiresReview() throws {
        let first = try RecordingAssessmentTestSupport.track(moving: true)
        let second = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            longitude: -74,
            moving: true,
            region: .newYork,
        )
        #expect(try assess(first + second).allSatisfy {
            $0.selection == .conflict([
                RecordingAssessmentTestSupport.first,
                RecordingAssessmentTestSupport.second,
            ])
        })
    }

    @Test func silenceDoesNotProduceACompetitorOrExtendAnOldPosition() throws {
        let moving = try RecordingAssessmentTestSupport.track(moving: true)
        #expect(try assess(moving)
            .allSatisfy {
                $0.selection == .onlyAvailableDevice(RecordingAssessmentTestSupport.first)
            })
        let point = try RecordingAssessmentTestSupport.observation(seconds: 0)
        let result = try MultiDeviceAssessment.assess(
            observations: [point],
            within: RecordingAssessmentTestSupport.period(1, 7200),
            places: [],
        )
        #expect(result.map(\.selection) == [.noEvidence])
    }

    @Test func equalUnknownGeographyDoesNotImplyAgreementOrConflict() throws {
        let first = try RecordingAssessmentTestSupport.track(moving: false, region: nil)
        let second = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            moving: false,
            region: nil,
        )
        #expect(try assess(first + second).allSatisfy {
            $0.selection == .uncertain([
                RecordingAssessmentTestSupport.first,
                RecordingAssessmentTestSupport.second,
            ])
        })
    }

    @Test func overlappingDifferentRecordingDaysConflictEvenWhenRegionsAgree() throws {
        let zone = try #require(TimeZone(secondsFromGMT: -3600))
        let first = try [0.0, 600, 1200]
            .map { try RecordingAssessmentTestSupport.observation(seconds: $0) }
        let second = try [0.0, 600, 1200].map { try RecordingAssessmentTestSupport.observation(
            deviceID: RecordingAssessmentTestSupport.second,
            seconds: $0,
            timeZone: zone,
        ) }
        #expect(try assess(first + second).allSatisfy {
            $0.selection == .conflict([
                RecordingAssessmentTestSupport.first,
                RecordingAssessmentTestSupport.second,
            ])
        })
    }

    @Test func equalUTCDateWithoutOverlapDoesNotCreateAConflict() throws {
        let early = try RecordingAssessmentTestSupport.observation(seconds: 0)
        let later = try RecordingAssessmentTestSupport.observation(
            deviceID: RecordingAssessmentTestSupport.second,
            seconds: 600,
            region: .newYork,
        )
        let result = try assess([early, later])
        #expect(result.map(\.selection) == [
            .onlyAvailableDevice(RecordingAssessmentTestSupport.first),
            .noEvidence,
            .onlyAvailableDevice(RecordingAssessmentTestSupport.second),
            .noEvidence,
        ])
    }

    @Test func inputOrderAndDuplicateDeliveryDoNotChangeAssessment() throws {
        let evidence = try RecordingAssessmentTestSupport.track(moving: true)
            + RecordingAssessmentTestSupport.track(
                deviceID: RecordingAssessmentTestSupport.second,
                longitude: -74,
                moving: false,
                region: .newYork,
            )
        #expect(try assess(evidence) == assess(evidence.reversed() + evidence))
    }

    @Test func rejectsDifferentPayloadsForOneSampleIdentity() throws {
        let first = try RecordingAssessmentTestSupport.observation(seconds: 0)
        let collision = try RecordingAssessmentTestSupport.observation(
            seconds: 10,
            sampleID: first.sample.id,
        )
        #expect(throws: MultiDeviceAssessment.ValidationError.self) {
            try assess([first, collision])
        }
    }
}
