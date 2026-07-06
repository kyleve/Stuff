@_spi(Testing) import ForemanCore
import Foundation
import Testing

/// A `SleepAssertionBackend` that counts transitions instead of taking a
/// real assertion — shared by the inhibitor and supervisor suites.
@MainActor
final class SleepAssertionRecorder: SleepAssertionBackend {
    private(set) var begins = 0
    private(set) var ends = 0

    func begin(reason _: String) {
        begins += 1
    }

    func end() {
        ends += 1
    }
}

/// A `LoginItemBackend` that records register/unregister/open calls in memory
/// and can be told to fail, so login-item wiring is testable without touching
/// the real `SMAppService`.
@MainActor
final class LoginItemRecorder: LoginItemBackend {
    private(set) var status: LoginItemStatus
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openCount = 0

    /// When set, both `register()` and `unregister()` throw it (and leave
    /// `status` unchanged), simulating an `SMAppService` failure.
    var failure: (any Error)?

    init(status: LoginItemStatus = .notRegistered, failure: (any Error)? = nil) {
        self.status = status
        self.failure = failure
    }

    func register() throws {
        registerCount += 1
        if let failure { throw failure }
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        if let failure { throw failure }
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {
        openCount += 1
    }
}

/// A stand-in error for login-item failure injection.
struct LoginItemTestError: Error {}

/// A ``RepoCopyRemoving`` double that records its calls and, by default,
/// actually deletes the copy directory so a follow-up rescan behaves like a
/// real removal — without shelling out to `git` or touching the user's Trash.
/// Only touched on the main actor in practice.
final class RecordingCopyRemover: RepoCopyRemoving, @unchecked Sendable {
    struct WorktreeRemoval: Equatable {
        let path: URL
        let parentRepoPath: URL
    }

    private(set) var worktreeRemovals: [WorktreeRemoval] = []
    private(set) var cloneRemovals: [URL] = []
    /// When set, every removal throws it (before deleting), simulating a git
    /// or Trash failure.
    var failure: (any Error)?
    /// Whether a successful removal also deletes the directory on disk.
    var deletesDirectory = true

    func removeWorktree(at path: URL, parentRepoPath: URL) throws {
        worktreeRemovals.append(WorktreeRemoval(path: path, parentRepoPath: parentRepoPath))
        if let failure { throw failure }
        if deletesDirectory {
            try? FileManager.default.removeItem(at: path)
        }
    }

    func removeClone(at path: URL) throws {
        cloneRemovals.append(path)
        if let failure { throw failure }
        if deletesDirectory {
            try? FileManager.default.removeItem(at: path)
        }
    }
}

/// A stand-in error for copy-removal failure injection.
struct CopyRemovalTestError: Error {}

/// A `ForemanServices` wired for control-socket tests: a real scan directory
/// with `.git`-bearing repos, a long-running stub `cursor-agent`, and a
/// ``RecordingCopyRemover`` so removals are observable and hermetic.
struct ControlServicesFixture {
    let services: ForemanServices
    let store: WorkerConfigStore
    let base: URL
    let scanDirectory: URL
    let executable: URL
    let remover: RecordingCopyRemover
}

/// Builds a ``ControlServicesFixture`` with `repoNames` created as
/// `.git`-bearing directories under the scan directory. The returned services
/// have not been `start()`ed yet.
@MainActor
func makeControlServicesFixture(repoNames: [String]) throws -> ControlServicesFixture {
    let base = try makeTemporaryDirectory()
    let scanDirectory = base.appendingPathComponent("Development", isDirectory: true)
    try FileManager.default.createDirectory(at: scanDirectory, withIntermediateDirectories: true)
    for name in repoNames {
        try addGitDirectory(name, in: scanDirectory)
    }
    let executable = try makeStubExecutable(
        in: base,
        script: "#!/bin/sh\nwhile true; do sleep 0.1; done\n",
    )
    let store = WorkerConfigStore(directory: base.appendingPathComponent("config"))
    try store.save(ForemanConfiguration(
        scanDirectory: scanDirectory,
        agentExecutable: executable,
        repos: [:],
    ))
    let remover = RecordingCopyRemover()
    let services = ForemanServices(
        configStore: store,
        logDirectory: base.appendingPathComponent("logs"),
        sleepInhibitor: SleepInhibitor(backend: SleepAssertionRecorder()),
        loginItem: LoginItemController(backend: LoginItemRecorder()),
        copyRemover: remover,
    )
    return ControlServicesFixture(
        services: services,
        store: store,
        base: base,
        scanDirectory: scanDirectory,
        executable: executable,
        remover: remover,
    )
}

/// Creates `<directory>/<name>/.git` (a directory `.git`, as a plain clone
/// has), enough for discovery and adopt validation.
func addGitDirectory(_ name: String, in directory: URL) throws {
    try FileManager.default.createDirectory(
        at: directory.appendingPathComponent("\(name)/.git", isDirectory: true),
        withIntermediateDirectories: true,
    )
}

/// Builds a live `Repo` over a fixed executable for tree-level tests:
/// disabled, unfavorited, standard options, no-op persistence and
/// state-change hooks.
@MainActor
func makeStubRepo(
    scanned: ScannedRepo,
    logDirectory: URL,
    executable: URL,
    provenance: CopyProvenance? = nil,
) -> Repo {
    Repo(
        scanned: scanned,
        isEnabled: false,
        isFavorite: false,
        options: .standard,
        provenance: provenance,
        worker: Worker(
            name: scanned.name,
            workerDirectory: scanned.rootURL,
            logDirectory: logDirectory,
            onStateChange: {},
        ),
        resolveExecutable: { executable },
        onPersistentChange: { _ in },
    )
}

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
