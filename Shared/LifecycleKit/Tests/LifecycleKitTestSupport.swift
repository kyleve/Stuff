import Testing

private struct WaitTimeoutError: Error {}

/// Polls `condition` on the main actor until it holds or the timeout elapses.
/// Sleeping yields to the runner's drive task between checks.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline {
            throw WaitTimeoutError()
        }
        try await Task.sleep(for: .milliseconds(1))
    }
}
