import Foundation
@testable import SnapshotKitTesting
import Testing

struct SnapshotSampleStabilityTests {
    @Test func identicalSamplesMatch() {
        let sample = Data([0, 100, 200, 255])
        #expect(SnapshotSampleStability.matches(sample, anchor: sample))
    }

    @Test func adjacentQuantizationValuesMatch() {
        #expect(SnapshotSampleStability.matches(
            Data([1, 99, 201, 254]),
            anchor: Data([0, 100, 200, 255]),
        ))
    }

    @Test func aSingleChannelBeyondOneUnitDoesNotMatch() {
        #expect(SnapshotSampleStability.matches(
            Data([0, 100, 202, 255]),
            anchor: Data([0, 100, 200, 255]),
        ) == false)
    }

    @Test func cumulativeDriftDoesNotMatchTheFixedAnchor() {
        let anchor = Data([100])
        #expect(SnapshotSampleStability.matches(Data([101]), anchor: anchor))
        #expect(SnapshotSampleStability.matches(Data([102]), anchor: Data([101])))
        #expect(SnapshotSampleStability.matches(Data([102]), anchor: anchor) == false)
    }

    @Test func changesBeyondAStaticPrefixDoNotMatch() {
        let anchor = Data(repeating: 100, count: 4096)
        var sample = anchor
        sample[sample.count - 1] = 102
        #expect(SnapshotSampleStability.matches(sample, anchor: anchor) == false)
    }

    @Test func missingOrResizedSamplesDoNotMatch() {
        #expect(SnapshotSampleStability.matches(Data(), anchor: Data()) == false)
        #expect(SnapshotSampleStability.matches(nil, anchor: nil) == false)
        #expect(SnapshotSampleStability.matches(Data([0]), anchor: nil) == false)
        #expect(SnapshotSampleStability.matches(nil, anchor: Data([0])) == false)
        #expect(SnapshotSampleStability.matches(Data([0, 0]), anchor: Data([0])) == false)
    }
}
