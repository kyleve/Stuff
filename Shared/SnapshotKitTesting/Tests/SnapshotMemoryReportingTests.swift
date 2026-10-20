import Foundation
@_spi(Testing) import SnapshotKitTesting
import Testing

@MainActor
struct SnapshotMemoryReportingTests {
    @Test func disabledReportingProducesNoSample() throws {
        #expect(try SnapshotMemoryReporting.line(
            reference: URL(fileURLWithPath: "/tmp/disabled.png"),
            isEnabled: false,
        ) == nil)
    }

    @Test func reportsProcessMemoryWithoutEmittingACapture() throws {
        let reference = URL(fileURLWithPath: "/tmp/__Snapshots__/Suite/cutsheet.png")
        let payload = try SnapshotMemoryReporting.line(reference: reference, isEnabled: true)
        let json = try #require(payload)
        let sample = try JSONDecoder().decode(Sample.self, from: Data(json.utf8))
        #expect(sample.reference == reference.absoluteString)
        #expect(sample.processID == ProcessInfo.processInfo.processIdentifier)
        #expect(sample.memory.footprintBytes > 0)
        #expect(sample.memory.peakFootprintBytes >= Int64(sample.memory.footprintBytes))
        #expect(sample.memory.residentBytes > 0)
        #expect(sample.memory.peakResidentBytes >= sample.memory.residentBytes)
    }

    private struct Sample: Decodable {
        let reference: String
        let processID: Int32
        let memory: Memory
    }

    private struct Memory: Decodable {
        let footprintBytes: UInt64
        let peakFootprintBytes: Int64
        let residentBytes: UInt64
        let peakResidentBytes: UInt64
    }
}
