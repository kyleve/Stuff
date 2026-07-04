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

/// Writes an executable shell script into `directory` and returns its URL.
func makeStubExecutable(
    in directory: URL,
    named name: String = "stub-agent",
    script: String,
) throws -> URL {
    let url = directory.appendingPathComponent(name)
    try Data(script.utf8).write(to: url)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: url.path,
    )
    return url
}

/// The failure `waitUntil` throws when its condition never holds.
struct WaitTimeoutError: Error {}

/// Polls `condition` until it holds, failing the test if `timeout` elapses
/// first. Prefer this over fixed sleeps — fixed delays flake under load.
///
/// Throws on timeout (after recording the issue) so the test stops instead of
/// running its remaining assertions against a state that never materialized.
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
    throw WaitTimeoutError()
}
