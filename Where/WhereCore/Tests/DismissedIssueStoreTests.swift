import Foundation
import Testing
import WhereCore

struct DismissedIssueStoreTests {
    @Test func setIssueDismissed_roundTrips() async throws {
        let store = try SwiftDataStore.inMemory()
        let key = "borderDrift:1234567890"

        try await store.perform {
            try await store.setIssueDismissed(true, key: key)
        }
        var keys = try await store.dismissedIssueKeys()
        #expect(keys == [key])

        try await store.perform {
            try await store.setIssueDismissed(false, key: key)
        }
        keys = try await store.dismissedIssueKeys()
        #expect(keys.isEmpty)
    }

    @Test func setIssueDismissed_upsertIsIdempotent() async throws {
        let store = try SwiftDataStore.inMemory()
        let key = "abruptChange:1:2"

        try await store.perform {
            try await store.setIssueDismissed(true, key: key)
            try await store.setIssueDismissed(true, key: key)
        }
        let keys = try await store.dismissedIssueKeys()
        #expect(keys == [key])
    }

    @Test func clearAll_wipesDismissals() async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform {
            try await store.setIssueDismissed(true, key: "missingDays:1")
        }
        try await store.perform {
            try await store.clearAll()
        }
        let keys = try await store.dismissedIssueKeys()
        #expect(keys.isEmpty)
    }

    @Test func allDismissedIssues_returnsKeysAndTimestamps() async throws {
        let store = try SwiftDataStore.inMemory()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.perform {
            try await store.restoreDismissedIssue(
                DismissedIssue(key: "borderDrift:1700000000", dismissedAt: when),
            )
        }

        let dismissed = try await store.allDismissedIssues()
        #expect(dismissed == [DismissedIssue(key: "borderDrift:1700000000", dismissedAt: when)])
    }

    @Test func restoreDismissedIssue_preservesTimestampAndUpsertsByKey() async throws {
        let store = try SwiftDataStore.inMemory()
        let key = "abruptChange:1:2"
        let original = Date(timeIntervalSince1970: 1_700_000_000)
        let replacement = Date(timeIntervalSince1970: 1_700_500_000)

        try await store.perform {
            try await store.restoreDismissedIssue(DismissedIssue(key: key, dismissedAt: original))
        }
        #expect(try await store.allDismissedIssues().first?.dismissedAt == original)

        // Restoring the same key again upserts (no duplicate) and the imported
        // timestamp wins.
        try await store.perform {
            try await store.restoreDismissedIssue(DismissedIssue(
                key: key,
                dismissedAt: replacement,
            ))
        }
        let dismissed = try await store.allDismissedIssues()
        #expect(dismissed == [DismissedIssue(key: key, dismissedAt: replacement)])
    }
}
