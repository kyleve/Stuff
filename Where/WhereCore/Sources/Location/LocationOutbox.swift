import Foundation
import PeriscopeCore

/// A durable backlog of GPS samples that failed to persist, so a transient
/// store outage (SwiftData/CloudKit) that *outlives the process* doesn't
/// silently drop measurements: the backlog is reloaded and re-tried on the next
/// `LocationIngestor.start()`.
///
/// Deliberately separate from `WhereStore`: the store is the thing that's
/// failing when samples land here, so the backlog must not depend on it. The
/// production implementation is a small atomically-written JSON file in the
/// app's own sandbox (the samples are sensitive raw locations — not the App
/// Group the widget reads).
public protocol LocationOutbox: Sendable {
    /// The persisted backlog, or empty when there's none / it can't be read.
    func load() async -> [LocationSample]
    /// Replace the persisted backlog with `samples`; an empty array clears it.
    func save(_ samples: [LocationSample]) async
}

/// A no-op outbox: nothing is persisted, so the retry queue is in-memory only
/// (the pre-durability behavior). The safe default for previews/tests and a
/// fallback when no durable location is available.
public struct NoOpLocationOutbox: LocationOutbox {
    public init() {}
    public func load() async -> [LocationSample] {
        []
    }

    public func save(_: [LocationSample]) async {}
}

/// File-backed `LocationOutbox`: the backlog is one atomically-written JSON file
/// (write-to-temp-then-rename), so a crash mid-write can never corrupt a
/// previously good backlog. An `actor` so its disk I/O runs off the
/// `LocationIngestor`'s executor.
public actor FileLocationOutbox: LocationOutbox {
    private let fileURL: URL

    private static let logger = WhereLog.location(LocationOutboxLog.self)

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// An outbox at the app sandbox's Application Support directory, or a
    /// `NoOpLocationOutbox` if that can't be resolved (so ingestion still works,
    /// just without cross-launch durability).
    public static func applicationSupport(
        fileManager: FileManager = .default,
    ) -> any LocationOutbox {
        guard let directory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true,
        ) else {
            logger { .noApplicationSupport }
            return NoOpLocationOutbox()
        }
        return FileLocationOutbox(fileURL: directory.appending(path: "location-retry-outbox.json"))
    }

    public func load() async -> [LocationSample] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode([LocationSample].self, from: data)
        } catch {
            // A decode failure means a corrupt or stale-format file; drop it
            // rather than crash-looping on every launch.
            Self.logger(attachments: [.error(error, name: "read-error")]) {
                .droppedUnreadableBacklog(description: error.localizedDescription)
            }
            return []
        }
    }

    public func save(_ samples: [LocationSample]) async {
        guard !samples.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        do {
            let data = try JSONEncoder().encode(samples)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger(attachments: [.error(error, name: "persist-error")]) {
                .persistBacklogFailed(description: error.localizedDescription)
            }
        }
    }
}
