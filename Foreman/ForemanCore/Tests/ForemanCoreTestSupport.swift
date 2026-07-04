import Foundation
import Testing

/// Creates a unique empty directory under the system temporary directory.
/// Callers don't need to remove it; the OS reaps temp storage.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ForemanCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Polls `condition` until it holds, failing the test if `timeout` elapses
/// first. Prefer this over fixed sleeps — fixed delays flake under load.
func waitUntil(
    timeout: Duration = .seconds(5),
    _ comment: Comment,
    condition: @MainActor () -> Bool,
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for condition: \(comment)")
}
