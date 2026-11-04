import Foundation
import Synchronization

/// Fails the next sidecar preparation after the separate Keychain write can commit.
final class FailingInstallationSidecarFileManager: FileManager, @unchecked Sendable {
    private let shouldFail = Mutex(false)

    func failNextWrite() {
        shouldFail.withLock { $0 = true }
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil,
    ) throws {
        if shouldFail.withLock({ value in
            let previous = value
            value = false
            return previous
        }) {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try super.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes,
        )
    }
}
