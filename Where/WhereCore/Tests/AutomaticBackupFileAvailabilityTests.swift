import Foundation
import Testing
@testable import WhereCore

struct AutomaticBackupFileAvailabilityTests {
    @Test func anOrdinaryLocalFileNeedsNoDownload() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try SystemAutomaticBackupFileAvailability().isDownloaded(at: file))
    }
}
