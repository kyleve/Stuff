import WhereCore

/// Holds a store factory at its suspension boundary and counts actual opens.
actor StoreOpeningProbe {
    private var continuation: CheckedContinuation<SwiftDataStore, Error>?
    private var arrival: CheckedContinuation<Void, Never>?
    private(set) var count = 0

    func open() async throws -> SwiftDataStore {
        count += 1
        return try await withCheckedThrowingContinuation {
            continuation = $0
            arrival?.resume()
            arrival = nil
        }
    }

    func waitUntilOpen() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func complete(_ result: Result<SwiftDataStore, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
