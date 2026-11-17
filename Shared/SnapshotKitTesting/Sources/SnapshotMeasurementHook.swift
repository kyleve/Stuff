import Foundation

private enum SnapshotReadinessHookResult {
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
    try await runSnapshotReadinessHook(
        maximumDuration: maximumDuration,
        invalidTimeout: .invalidMeasurementHookTimeout(name: name, budget: maximumDuration),
        timedOut: .measurementReadinessTimedOut(name: name, budget: maximumDuration),
        hook: hook,
    )
}

/// Bounds fixture readiness while the capture host is mounted, before settling.
@MainActor
@_spi(Testing) public func runSnapshotPreparationHook(
    named name: String,
    maximumDuration: TimeInterval,
    hook: @MainActor @escaping () async throws -> Void,
) async throws {
    try await runSnapshotReadinessHook(
        maximumDuration: maximumDuration,
        invalidTimeout: .invalidCapturePreparationTimeout(name: name, budget: maximumDuration),
        timedOut: .capturePreparationTimedOut(name: name, budget: maximumDuration),
        hook: hook,
    )
}

@MainActor
private func runSnapshotReadinessHook(
    maximumDuration: TimeInterval,
    invalidTimeout: SnapshotRenderingError,
    timedOut: SnapshotRenderingError,
    hook: @MainActor @escaping () async throws -> Void,
) async throws {
    try Task.checkCancellation()
    guard maximumDuration.isFinite, maximumDuration > 0 else {
        throw invalidTimeout
    }
    let result = try await withThrowingTaskGroup(of: SnapshotReadinessHookResult.self) { group in
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
            throw timedOut
        case .cancelled:
            throw CancellationError()
    }
}
