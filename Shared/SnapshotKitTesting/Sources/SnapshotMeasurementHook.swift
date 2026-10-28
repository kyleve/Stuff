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
    hook: @MainActor @escaping () async throws -> Void,
) async throws {
    try Task.checkCancellation()
    guard maximumDuration.isFinite, maximumDuration > 0 else {
        throw SnapshotRenderingError.invalidMeasurementHookTimeout(
            name: name,
            budget: maximumDuration,
        )
    }
    let result = try await withThrowingTaskGroup(of: SnapshotMeasurementHookResult.self) { group in
        group.addTask {
            try await hook()
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

        defer { group.cancelAll() }
        return try await group.next() ?? .cancelled
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
