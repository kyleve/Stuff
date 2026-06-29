import Foundation
import SwiftData

/// Error a test injects into a teardown handler to exercise the park-safe paths.
enum StorageTestError: Error, Equatable {
    case injected
}

/// A `@Model` fixture for `modelContainer(for:)` tests.
@Model
final class Note {
    var text: String

    init(text: String) {
        self.text = text
    }
}

/// Records the order teardown handlers fire in, so a test can assert phase
/// ordering and children-first traversal.
actor CallLog {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}

/// Throws `StorageTestError.injected` the first time it's fired and succeeds
/// afterwards — used to verify a parked teardown completes on retry.
actor ThrowOnce {
    private var armed = true

    func fireIfArmed() throws {
        if armed {
            armed = false
            throw StorageTestError.injected
        }
    }
}

/// Records whether a vend attempted from inside a teardown handler was rejected,
/// so a test can prove the subtree refuses vends while it is being deleted.
actor VendOutcome {
    private(set) var wasRejected: Bool?

    func record(rejected: Bool) {
        wasRejected = rejected
    }
}

/// A fresh, unique temporary directory for a `.custom` base, isolating each test
/// from the others and from the host's real Application Support.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "StorageKitTests-\(UUID().uuidString)",
        directoryHint: .isDirectory,
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
