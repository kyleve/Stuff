import Foundation
import Testing
import WhereCore

struct DismissedIssueStoreTests {
    private static let borderDrift = DataIssueID.borderDrift(
        day: CalendarDay(year: 2026, month: 4, day: 1),
    )
    private static let abruptChange = DataIssueID.abruptChange(
        earlier: CalendarDay(year: 2026, month: 1, day: 1),
        later: CalendarDay(year: 2026, month: 1, day: 2),
    )
    private static let missingDays = DataIssueID.missingDays(
        start: CalendarDay(year: 2026, month: 1, day: 5),
    )

    @Test func setIssueDismissed_roundTrips() async throws {
        let store = try SwiftDataStore.inMemory()
        let id = Self.borderDrift

        try await store.perform {
            try await store.setIssueDismissed(true, id: id)
        }
        var ids = try await store.dismissedIssueIDs()
        #expect(ids == [id])

        try await store.perform {
            try await store.setIssueDismissed(false, id: id)
        }
        ids = try await store.dismissedIssueIDs()
        #expect(ids.isEmpty)
    }

    @Test func setIssueDismissed_upsertIsIdempotent() async throws {
        let store = try SwiftDataStore.inMemory()
        let id = Self.abruptChange

        try await store.perform {
            try await store.setIssueDismissed(true, id: id)
            try await store.setIssueDismissed(true, id: id)
        }
        let ids = try await store.dismissedIssueIDs()
        #expect(ids == [id])
    }

    @Test func rotatingTheDataEpochWipesDismissals() async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform {
            try await store.setIssueDismissed(true, id: Self.missingDays)
        }
        try await store.perform {
            _ = try await store.rotateDataEpoch(
                reason: .accountReset,
                changedBy: RecordingDeviceID(rawValue: UUID()),
                at: Date(timeIntervalSinceReferenceDate: 1),
            )
        }
        let ids = try await store.dismissedIssueIDs()
        #expect(ids.isEmpty)
    }

    @Test func allDismissedIssues_returnsIDsAndTimestamps() async throws {
        let store = try SwiftDataStore.inMemory()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.perform {
            try await store.restoreDismissedIssue(
                DismissedIssue(id: Self.borderDrift, dismissedAt: when),
            )
        }

        let dismissed = try await store.allDismissedIssues()
        #expect(dismissed == [DismissedIssue(id: Self.borderDrift, dismissedAt: when)])
    }

    @Test func restoreDismissedIssue_preservesTimestampAndUpsertsByID() async throws {
        let store = try SwiftDataStore.inMemory()
        let id = Self.abruptChange
        let original = Date(timeIntervalSince1970: 1_700_000_000)
        let replacement = Date(timeIntervalSince1970: 1_700_500_000)

        try await store.perform {
            try await store.restoreDismissedIssue(DismissedIssue(id: id, dismissedAt: original))
        }
        #expect(try await store.allDismissedIssues().first?.dismissedAt == original)

        // Restoring the same id again upserts (no duplicate) and the imported
        // timestamp wins.
        try await store.perform {
            try await store.restoreDismissedIssue(DismissedIssue(
                id: id,
                dismissedAt: replacement,
            ))
        }
        let dismissed = try await store.allDismissedIssues()
        #expect(dismissed == [DismissedIssue(id: id, dismissedAt: replacement)])
    }
}
