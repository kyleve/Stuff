import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct RecordingDeviceRemovalFilterTests {
    private static let phone = RecordingDeviceID(rawValue: UUID())
    private static let tablet = RecordingDeviceID(rawValue: UUID())
    private static let cutoff = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func hidesTargetSamplesAtAndAfterTheEarliestRemoval() {
        let samples = [
            Self.sample(deviceID: Self.phone, offset: -1),
            Self.sample(deviceID: Self.phone, offset: 0),
            Self.sample(deviceID: Self.phone, offset: 1),
            Self.sample(deviceID: Self.tablet, offset: 1),
        ]
        let removals = [
            Self.removal(deviceID: Self.phone, offset: 10),
            Self.removal(deviceID: Self.phone, offset: 0),
        ]

        let visible = RecordingDeviceRemovalFilter.visibleSamples(samples, removals: removals)

        #expect(visible.map(\.id) == [samples[0].id, samples[3].id])
    }

    @Test func unattributedAndManualSamplesRemainVisible() {
        let unattributed = LocationSample(
            timestamp: Self.cutoff,
            coordinate: Coordinate(latitude: 1, longitude: 2),
            horizontalAccuracy: 3,
            source: .gpsVisit,
        )
        let manual = LocationSample(
            timestamp: Self.cutoff,
            coordinate: Coordinate(latitude: 1, longitude: 2),
            horizontalAccuracy: 3,
            source: .manual,
            recordingDeviceID: Self.phone,
        )

        #expect(RecordingDeviceRemovalFilter.visibleSamples(
            [unattributed, manual],
            removals: [Self.removal(deviceID: Self.phone, offset: 0)],
        ).count == 2)
    }

    private static func removal(
        deviceID: RecordingDeviceID,
        offset: TimeInterval,
    ) -> RecordingDeviceRemoval {
        RecordingDeviceRemoval(
            id: UUID(),
            deviceID: deviceID,
            removedAt: cutoff.addingTimeInterval(offset),
            removedByDeviceID: tablet,
        )
    }

    private static func sample(
        deviceID: RecordingDeviceID,
        offset: TimeInterval,
    ) -> LocationSample {
        LocationSample(
            timestamp: cutoff.addingTimeInterval(offset),
            coordinate: Coordinate(latitude: 1, longitude: 2),
            horizontalAccuracy: 3,
            source: .gpsVisit,
            recordingDeviceID: deviceID,
        )
    }
}
