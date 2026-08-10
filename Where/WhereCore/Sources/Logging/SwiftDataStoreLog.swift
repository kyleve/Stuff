import PeriscopeCore

/// Structured events for `SwiftDataStore` — store open (with the resolved
/// on-disk path / App Group state) and the data-integrity guards. A dropped
/// corrupt record is a programmer error, so it logs at `.fault`.
enum SwiftDataStoreLog: LogEvent {
    /// Names the store's timed spans (`log.measure(.open) { … }`).
    ///
    /// Only the reads a normal session leans on are spanned, and only where the
    /// row count grows with the user's history: the small fixed-size fetches
    /// (tracked/primary regions, dismissals) would add records to every store
    /// change without ever explaining a slow screen, and the whole-table reads
    /// belong to the backup export that spans itself. Leaves like these carry no
    /// budget — the operation that asked for them does.
    enum SpanName: Hashable {
        case open
        /// A windowed GPS-sample fetch — the query behind every year report.
        case fetchSamples
        /// A day-range manual-day fetch.
        case fetchManualDays
        /// A windowed evidence fetch.
        case fetchEvidence
        /// One evidence blob, read out of external storage.
        case fetchEvidenceBlob
        /// The outermost `perform` of a write transaction, up to and including
        /// the save — so every batched mutation lands in one measured commit.
        case commit
    }

    /// Opened an in-memory store (tests/previews).
    case openedInMemory(mode: String)
    /// Opened the on-disk store, reporting whether the App Group container
    /// resolved and the resolved database URL.
    case openedOnDisk(mode: String, appGroupResolved: Bool, url: String)
    /// Ignored tracked-region ids the current catalog doesn't know (a store
    /// written by a newer catalog version). The ids persist as a structured
    /// list; formatting is done at display time (see `message`).
    case ignoredUnknownTrackedRegions(ids: [String])
    /// Ignored primary-region ids the current catalog doesn't know (a store
    /// written by a newer catalog version).
    case ignoredUnknownPrimaryRegions(ids: [String])
    /// Dropped a record that failed to materialize into a domain value.
    case droppedCorruptRecord(type: String)
    /// Chose a deterministic value when CloudKit delivered conflicting rows for an immutable id.
    case resolvedConflictingImmutableRecords(type: String, id: String, count: Int)
    /// Persistent history could not distinguish a local save from an external import; the
    /// observer fails open and performs the remote reconciliation rather than miss new data.
    case remoteChangeClassificationFailed(description: String)

    static let eventName = "SwiftDataStore"

    var level: LogLevel {
        switch self {
            case .openedInMemory, .openedOnDisk: .info
            case .ignoredUnknownTrackedRegions,
                 .ignoredUnknownPrimaryRegions,
                 .remoteChangeClassificationFailed:
                .warning
            case .droppedCorruptRecord, .resolvedConflictingImmutableRecords: .fault
        }
    }

    var message: String {
        switch self {
            case let .openedInMemory(mode):
                "Opened SwiftData store (mode: \(mode))"
            case let .openedOnDisk(mode, appGroupResolved, url):
                "Opened SwiftData store (mode: \(mode), appGroupResolved: \(appGroupResolved), url: \(url))"
            case let .ignoredUnknownTrackedRegions(ids):
                "Ignored \(ids.count) unknown tracked-region id(s): \(ids.joined(separator: ", "))"
            case let .ignoredUnknownPrimaryRegions(ids):
                "Ignored \(ids.count) unknown primary-region id(s): \(ids.joined(separator: ", "))"
            case let .droppedCorruptRecord(type):
                "Dropped corrupt SwiftData record of type \(type)"
            case let .resolvedConflictingImmutableRecords(type, id, count):
                "Resolved \(count) conflicting immutable \(type) records for id \(id)"
            case let .remoteChangeClassificationFailed(description):
                "Could not classify persistent-store change; reconciling defensively: \(description)"
        }
    }
}
