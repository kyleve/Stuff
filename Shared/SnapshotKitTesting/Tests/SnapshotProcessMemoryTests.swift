@_spi(Testing) import SnapshotKitTesting
import Testing

struct SnapshotProcessMemoryTests {
    @Test func readsTheHostsCurrentUsageAndLifetimePeaks() throws {
        let memory = try SnapshotProcessMemory.current()
        #expect(memory.residentBytes > 0)
        #expect(memory.footprintBytes > 0)
        #expect(memory.peakResidentBytes >= memory.residentBytes)
        #expect(memory.peakFootprintBytes >= Int64(memory.footprintBytes))
    }
}
