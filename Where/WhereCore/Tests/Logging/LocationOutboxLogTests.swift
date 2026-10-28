import Foundation
import PeriscopeCore
import Testing
@testable import WhereCore

struct LocationOutboxLogTests {
    @Test func errorEventsPreserveMessagesAndRestrictedStructuredPayloads() throws {
        let original = NSError(
            domain: "PrivateLocation",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "unavailable"],
        )
        try verifyLocationErrorEvent(
            LocationOutboxLog.DroppedUnreadableBacklog(error: .restricted(.errorDetails, original)),
            name: "LocationOutbox.dropped-unreadable-backlog",
            message: "Dropping unreadable location retry backlog: unavailable",
            level: .error,
            original: original,
            externalID: nil,
        )
        try verifyLocationErrorEvent(
            LocationOutboxLog.ReadBacklogFailed(error: .restricted(.errorDetails, original)),
            name: "LocationOutbox.read-backlog-failed",
            message: "Failed to read location retry backlog; preserving it for retry: unavailable",
            level: .error,
            original: original,
            externalID: nil,
        )
        try verifyLocationErrorEvent(
            LocationOutboxLog.PersistBacklogFailed(error: .restricted(.errorDetails, original)),
            name: "LocationOutbox.persist-backlog-failed",
            message: "Failed to persist location retry backlog: unavailable",
            level: .error,
            original: original,
            externalID: nil,
        )
        try verifyLocationErrorEvent(
            LocationOutboxLog.ExcludeFromBackupFailed(error: .restricted(.errorDetails, original)),
            name: "LocationOutbox.exclude-from-backup-failed",
            message: "Failed to exclude location retry backlog from device backup: unavailable",
            level: .error,
            original: original,
            externalID: nil,
        )
        try verifyLocationErrorEvent(
            LocationOutboxLog.DiscardInsecureBacklogFailed(error: .restricted(
                .errorDetails,
                original,
            )),
            name: "LocationOutbox.discard-insecure-backlog-failed",
            message: "Failed to discard a backup-eligible location retry backlog: unavailable",
            level: .error,
            original: original,
            externalID: nil,
        )
    }
}
