import Foundation
import PeriscopeCore
import Testing
@testable import WhereCore

struct AutomaticBackupLogTests {
    @Test func errorsStayStructuredAndRestricted() throws {
        let original = NSError(domain: "BackupTest", code: 42)
        let event = AutomaticBackupLog.ICloudAccessFailed(
            error: .restricted(.errorDetails, original),
        )
        #expect(event.error == LogError(capturing: original))
        #expect(event.level == .warning)
        #expect(event.classifiedFields == [
            .restricted(key: LogFieldKey("error"), kind: .errorDetails),
        ])
        let decoded = try JSONDecoder().decode(
            AutomaticBackupLog.ICloudAccessFailed.self,
            from: JSONEncoder().encode(event),
        )
        #expect(decoded.error == event.error)

        let cleanup = AutomaticBackupLog.CleanupFailed(
            error: .restricted(.errorDetails, original),
        )
        #expect(cleanup.error == event.error)
        #expect(cleanup.classifiedFields == event.classifiedFields)
    }

    @Test func fileNamesAreRestricted() {
        let event = AutomaticBackupLog.IgnoredUnrecognizedFile(
            name: .restricted(.identifier, "private.wherebackup"),
        )
        #expect(event.classifiedFields == [
            .restricted(key: LogFieldKey("name"), kind: .identifier),
        ])
        #expect(AutomaticBackupLog.ICloudUnavailable().level == .warning)
    }
}
