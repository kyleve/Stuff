import Foundation
import StuffToolCore
import Testing

struct SnapshotLogReportTests {
    @Test func aggregatesTimingsAndSortsDifferencesByMaximumDelta() throws {
        let log = Data("""
        detail SNAPSHOT_TIMING {"id":"slow","total":2.0,"phases":{"draw":1.5,"settle":0.5,"intrinsicMeasure":0.4},"settlePasses":3,"sizing":"fullContent","measurementReadiness":"ready","captureSettle":"stable"}
        SNAPSHOT_TIMING {"id":"fast","total":1.0,"phases":{"draw":0.75,"settle":0.25,"intrinsicMeasure":0.1},"settlePasses":1,"sizing":"device","measurementReadiness":"ready","captureSettle":"stable"}
        SNAPSHOT_DIFF {"outcome":"differs","maxChannelDelta":4,"differingPixels":10,"differingFraction":0.1,"region":[1,2,3,4],"reference":"A/__Snapshots__/small.png"}
        SNAPSHOT_DIFF {"outcome":"differs","maxChannelDelta":200,"differingPixels":2,"differingFraction":0.01,"region":[5,6,7,8],"reference":"A/__Snapshots__/large.png"}
        """.utf8)

        let report = try SnapshotLogReport(logs: [log])
        let timings = report.timingText()
        let differences = report.differenceText(isRecording: false)

        #expect(timings.contains("2 captures, 3.0s total, 1.500s per image"))
        #expect(timings.contains("settle passes: min 1, max 3, mean 2.0"))
        let profile = report.profileTimingText()
        #expect(profile.contains("sizing:"))
        #expect(profile.contains("2  ready"))
        #expect(profile.contains("0.50s  ready (2 captures)"))
        let large = try #require(differences.range(of: "large.png"))
        let small = try #require(differences.range(of: "small.png"))
        #expect(large.lowerBound < small.lowerBound)
    }

    @Test func recordingSuppressesExpectedMissingReferences() throws {
        let log = Data("""
        SNAPSHOT_DIFF {"outcome":"referenceMissing","reference":"missing.png"}
        """.utf8)
        let report = try SnapshotLogReport(logs: [log])

        #expect(report.differenceText(isRecording: true) ==
            "  Every capture matched its reference byte for byte.\n")
    }

    @Test func malformedExternalRecordsFailRatherThanDisappear() {
        let log = Data("SNAPSHOT_TIMING {\"id\":\"missing-fields\"}\n".utf8)

        #expect(throws: (any Error).self) {
            _ = try SnapshotLogReport(logs: [log])
        }
    }
}
