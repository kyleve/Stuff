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
}
