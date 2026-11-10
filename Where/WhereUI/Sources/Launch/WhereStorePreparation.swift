import WhereCore

/// Shares one store open across overlapping onboarding and launch requests.
/// A cancelled waiter does not cancel the shared open. A failed open can be retried.
@MainActor
final class WhereStorePreparation {
    private final class Attempt {
        let task: Task<SwiftDataStore, Error>

        init(open: @escaping @Sendable () async throws -> SwiftDataStore) {
            task = Task.detached(priority: .userInitiated, operation: open)
        }
    }

    private let open: @Sendable () async throws -> SwiftDataStore
    private var attempt: Attempt?

    init(open: @escaping @Sendable () async throws -> SwiftDataStore) {
        self.open = open
    }

    func get() async throws -> SwiftDataStore {
        let current: Attempt
        if let attempt {
            current = attempt
        } else {
            current = Attempt(open: open)
            attempt = current
        }
        do {
            return try await current.task.value
        } catch {
            if attempt === current { attempt = nil }
            throw error
        }
    }
}
