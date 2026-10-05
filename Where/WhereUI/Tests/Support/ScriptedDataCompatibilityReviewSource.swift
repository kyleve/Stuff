import Foundation
import WhereCore

/// Deliberately ignores cancellation until released, to exercise stale preflight completions.
actor ScriptedDataCompatibilityReviewSource: DataCompatibilityReviewSource {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var pending: [Int: CheckedContinuation<DataCompatibilityActivationReview, any Error>] =
        [:]
    private(set) var requestedVersions: [DataCompatibilityVersion] = []

    init() {
        let channel = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        stream = channel.stream
        continuation = channel.continuation
    }

    nonisolated func updates() -> AsyncStream<Void> {
        stream
    }

    func notifyChange() {
        continuation.yield(())
    }

    func reviewActivation(requiring version: DataCompatibilityVersion) async throws
        -> DataCompatibilityActivationReview
    {
        let index = requestedVersions.count
        requestedVersions.append(version)
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }

    func complete(
        request index: Int,
        with result: Result<DataCompatibilityActivationReview, any Error>,
    ) {
        precondition(pending[index] != nil)
        pending.removeValue(forKey: index)?.resume(with: result)
    }

    func finish() {
        continuation.finish()
        for request in pending.values {
            request.resume(throwing: CancellationError())
        }
        pending.removeAll()
    }
}
