import SwiftData

/// Holds an async replacement factory after erasure so tests can cancel its caller.
actor InspectorStoreReopenGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    func open() async throws -> ModelContainer {
        await withCheckedContinuation {
            continuation = $0
            arrival?.resume()
            arrival = nil
        }
        try Task.checkCancellation()
        return try await makeContainer()
    }

    func waitUntilOpen() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
