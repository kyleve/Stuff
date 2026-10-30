@_spi(Testing) import SnapshotKitTesting

func snapshotRetryTimeout(attempt: Int, phase: String = "content") -> SnapshotRenderingError {
    .settleTimedOut(name: "retry-probe", phase: phase, viewType: "probe", budget: Double(attempt))
}

/// Reference identity verifies that retry orchestration preserves arbitrary errors.
final class SnapshotRetryProbeError: Error {}
