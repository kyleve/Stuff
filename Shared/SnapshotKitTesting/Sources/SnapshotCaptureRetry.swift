import UIKit

/// Retries only failed settling, with a fresh controller after each capture unwinds.
/// The capture operation must finish its teardown before returning or throwing.
@MainActor
@_spi(Testing) public enum SnapshotCaptureRetry {
    public static func capture<Output>(
        named name: String,
        makeViewController: () -> UIViewController,
        capture: (UIViewController) async throws -> Output,
        report: (String) -> Void,
    ) async throws -> Output {
        /// Scope the controller to one invocation so the retry loop cannot retain
        /// a failed host. The renderer owns containment and global-state cleanup.
        func attempt() async throws -> Output {
            let controller = makeViewController()
            return try await capture(controller)
        }

        return try await Self.capture(named: name, operation: attempt, report: report)
    }

    public static func capture<Output>(
        named name: String,
        operation: () async throws -> Output,
        report: (String) -> Void,
    ) async throws -> Output {
        let maximumAttempts = 3
        var attemptNumber = 1
        while true {
            try Task.checkCancellation()
            do {
                let result = try await operation()
                try Task.checkCancellation()
                if attemptNumber > 1 {
                    report(
                        "SNAPSHOT_RETRY \(singleLine(name)): recovered on attempt \(attemptNumber)/\(maximumAttempts)",
                    )
                }
                return result
            } catch {
                try Task.checkCancellation()
                guard let renderingError = error as? SnapshotRenderingError,
                      isRetryable(renderingError),
                      attemptNumber < maximumAttempts
                else { throw error }

                report(
                    "SNAPSHOT_RETRY \(singleLine(name)): attempt \(attemptNumber)/\(maximumAttempts) failed: "
                        +
                        "\(singleLine(renderingError.localizedDescription)); retrying attempt \(attemptNumber + 1)/\(maximumAttempts)",
                )
                attemptNumber += 1
                // Give lifecycle cancellation from the removed host a chance to
                // run. This is not a backoff or an extension of the settle budget.
                await Task.yield()
            }
        }
    }

    private static func isRetryable(_ error: SnapshotRenderingError) -> Bool {
        switch error {
            case .settleTimedOut, .settleStarved:
                true
            case .invalidSettleTimeoutMultiplier, .measurementHookRequiresIntrinsicSizing,
                 .measurementReadinessTimedOut, .invalidMeasurementHookTimeout,
                 .intrinsicHeightDidNotConverge, .fullContentSizeDidNotConverge,
                 .fullContentSizeExceedsLimit, .pngEncodingFailed, .missingCGImage:
                false
        }
    }

    private static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ")
    }
}
