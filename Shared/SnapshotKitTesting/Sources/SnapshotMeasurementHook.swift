import Foundation

private enum SnapshotMeasurementHookResult {
    case completed
    case timedOut
    case cancelled
}

/// Runs a pre-measure hook with a bounded lifetime, cancelling the losing side
/// of the race. Hooks that suspend must cooperate with cancellation so a timed
/// out capture can finish tearing down its hosted probe.
@MainActor
@_spi(Testing) public func runSnapshotMeasurementHook(
    named name: String,
    maximumDuration: TimeInterval,
    hook: @MainActor @escaping () async -> Void,
) async throws {
    try Task.checkCancellation()
    let result = await withTaskGroup(of: SnapshotMeasurementHookResult.self) { group in
        group.addTask {
            await hook()
            return .completed
        }
        group.addTask {
            do {
                try await Task.sleep(for: .seconds(maximumDuration))
                return .timedOut
            } catch {
                return .cancelled
            }
        }

        let first = await group.next() ?? .cancelled
        group.cancelAll()
        return first
    }

    try Task.checkCancellation()
    switch result {
        case .completed:
            return
        case .timedOut:
            throw SnapshotRenderingError.measurementReadinessTimedOut(
                name: name,
                budget: maximumDuration,
            )
        case .cancelled:
            throw CancellationError()
    }
}
