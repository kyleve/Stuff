import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct RecordingRecoveryExclusionTests {
    @Test func exclusionIsBoundToFormerTenureAndServerCutoff() {
        let owner = RecordingAuthority.Owner(
            deviceID: .init(rawValue: UUID()),
            tenureID: .init(rawValue: UUID()),
        )
        let cutoff = Date(timeIntervalSince1970: 2000)
        let exclusion = RecordingRecoveryExclusion(
            id: .init(rawValue: UUID()),
            formerOwner: owner,
            replacedAt: cutoff,
        )
        let raw = LocationSample(
            timestamp: cutoff,
            coordinate: .init(latitude: 40, longitude: -100),
            horizontalAccuracy: 5,
            source: .gpsVisit,
        )
        #expect(exclusion.excludes(raw.recorded(under: owner)))
        #expect(!exclusion.excludes(raw.recorded(by: owner.deviceID)))
        #expect(!exclusion.excludes(raw.recorded(under: .init(
            deviceID: owner.deviceID,
            tenureID: .init(rawValue: UUID()),
        ))))
        #expect(!exclusion.excludes(LocationSample(
            timestamp: cutoff.addingTimeInterval(-1),
            coordinate: raw.coordinate,
            horizontalAccuracy: 5,
            source: .gpsVisit,
        ).recorded(under: owner)))
        #expect(!exclusion.excludes(LocationSample(
            timestamp: cutoff,
            coordinate: raw.coordinate,
            horizontalAccuracy: 5,
            source: .manual,
        ).recorded(under: owner)))
    }
}
