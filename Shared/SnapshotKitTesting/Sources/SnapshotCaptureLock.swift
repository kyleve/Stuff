import Foundation

/// Serializes snapshot captures process-wide.
///
/// The capture pipeline is `@MainActor async` with long suspension points (the
/// settle loop, `onReadyToSnapshot` hooks), and while suspended it holds
/// process-global mutable state: the safe-area swizzle and its override
/// globals, the `UIView.setAnimationsEnabled` save/restore, and the one
/// `StuffTestHost` key window. Two interleaved captures corrupt all of them —
/// verified by the Phase 13 parallel-testing experiment, which produced 24+
/// spurious image mismatches. This lock makes that impossible: a capture that
/// starts while another is in flight parks here and runs when the first
/// finishes, in FIFO order.
///
/// Waiting is not cancellation-aware by design. A cancelled waiter stays in the
/// FIFO so its continuation cannot strand the lock. When its turn arrives, the
/// rendering pipeline observes cancellation before it hosts content, then this
/// type releases the lock normally.
///
/// Re-entering from a task that already holds the lock (an `onReadyToSnapshot`
/// hook rendering another snapshot) would deadlock, so it traps as a
/// programmer error instead.
@MainActor
enum SnapshotCaptureLock {
    private static var isHeld = false
    private static var waiters: [CheckedContinuation<Void, Never>] = []

    @TaskLocal private static var taskHoldsLock = false

    /// Runs `operation` while holding the process-wide capture lock, waiting
    /// (FIFO) for any in-flight capture to finish first.
    static func withLock<Output>(
        _ operation: @MainActor () async throws -> Output,
    ) async rethrows -> Output {
        precondition(
            !taskHoldsLock,
            """
            renderSnapshotImage was re-entered from within a capture (e.g. an \
            onReadyToSnapshot hook rendering another snapshot). Captures hold \
            process-global state and cannot nest.
            """,
        )
        await acquire()
        defer { release() }
        return try await $taskHoldsLock.withValue(true) {
            try await operation()
        }
    }

    private static func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        // Resumed by `release()`, which hands the (still-held) lock over.
    }

    private static func release() {
        guard !waiters.isEmpty else {
            isHeld = false
            return
        }
        waiters.removeFirst().resume()
    }
}
