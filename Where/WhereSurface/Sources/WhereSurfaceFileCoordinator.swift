import Foundation

/// Coordinates access to Where's App Group artifact across process boundaries.
///
/// Each call creates an `NSFileCoordinator` for that operation. It serializes
/// reads and writes with participating widget and helper processes; atomic writes
/// additionally keep the authoritative JSON from ever being partially written.
public struct WhereSurfaceFileCoordinator: Sendable {
    public init() {}

    /// Read the coordinated contents of `fileURL`, returning `nil` when the file
    /// has not been published yet.
    public func read(from fileURL: URL) throws -> Data? {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var accessError: (any Error)?
        var data: Data?

        coordinator.coordinate(
            readingItemAt: fileURL,
            options: .withoutChanges,
            error: &coordinationError,
        ) { coordinatedURL in
            do {
                data = try Data(contentsOf: coordinatedURL)
            } catch let error as NSError where Self.isMissingFile(error) {
                data = nil
            } catch {
                accessError = error
            }
        }

        if let coordinationError {
            guard Self.isMissingFile(coordinationError) else {
                throw coordinationError
            }
            return nil
        }
        if let accessError {
            throw accessError
        }
        return data
    }

    /// Atomically update `fileURL` while holding a coordinated write claim.
    public func write(_ data: Data, to fileURL: URL) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var accessError: (any Error)?

        coordinator.coordinate(
            writingItemAt: fileURL,
            // Foundation reserves `.forReplacing` for replacing the coordinated
            // item, not an atomic update of that item's contents.
            options: [],
            error: &coordinationError,
        ) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                accessError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let accessError {
            throw accessError
        }
    }

    private static func isMissingFile(_ error: NSError) -> Bool {
        error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
    }
}
