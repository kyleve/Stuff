import PeriscopeCore

/// Structured events and spans for `SwiftDataStore`.
@LogScope("SwiftDataStore")
enum SwiftDataStoreLog {
    enum SpanName: Hashable {
        case open
        case fetchSamples
        case fetchManualDays
        case fetchEvidence
        case fetchEvidenceBlob
        case commit
    }

    @LogEvent("opened-in-memory")
    struct OpenedInMemory {
        @LogField(exposure: .restricted, kind: .technicalState) var mode: String
        var message: String {
            "Opened SwiftData store (mode: \(mode))"
        }
    }

    @LogEvent("opened-on-disk")
    struct OpenedOnDisk {
        @LogField(exposure: .restricted, kind: .technicalState) var mode: String
        @LogField(exposure: .shareable, kind: .boolean)
        var appGroupResolved: Bool
        @LogField(exposure: .restricted, kind: .pathOrURL) var url: String
        var message: String {
            "Opened SwiftData store (mode: \(mode), appGroupResolved: "
                + "\(appGroupResolved), url: \(url))"
        }
    }

    @LogEvent("ignored-unknown-tracked-regions", level: .warning)
    struct IgnoredUnknownTrackedRegions {
        @LogField(exposure: .restricted, kind: .location) var ids: [String]
        @LogField(exposure: .shareable, kind: .count)
        var unknownRegionCount: Int
        var message: String {
            "Ignored \(ids.count) unknown tracked-region id(s): \(ids.joined(separator: ", "))"
        }
    }

    @LogEvent("ignored-unknown-primary-regions", level: .warning)
    struct IgnoredUnknownPrimaryRegions {
        @LogField(exposure: .restricted, kind: .location) var ids: [String]
        @LogField(exposure: .shareable, kind: .count)
        var unknownRegionCount: Int
        var message: String {
            "Ignored \(ids.count) unknown primary-region id(s): \(ids.joined(separator: ", "))"
        }
    }

    @LogEvent("dropped-corrupt-record", level: .fault)
    struct DroppedCorruptRecord {
        @LogField(exposure: .restricted, kind: .technicalState) var type: String
        var message: String {
            "Dropped corrupt SwiftData record of type \(type)"
        }
    }

    @LogEvent(
        "ignored-incomplete-sample-motion",
        level: .warning,
        message: "Preserved raw location while optional motion fields were incomplete",
    )
    struct IgnoredIncompleteSampleMotion {}

    @LogEvent("resolved-conflicting-immutable-records", level: .fault)
    struct ResolvedConflictingImmutableRecords {
        @LogField(exposure: .restricted, kind: .technicalState) var type: String
        @LogField(exposure: .restricted, kind: .identifier) var id: String
        @LogField("conflict_count", exposure: .shareable, kind: .count) var count: Int
        var message: String {
            "Resolved \(count) conflicting immutable \(type) records for id \(id)"
        }
    }

    @LogEvent("remote-change-classification-failed", level: .warning, version: 2)
    struct RemoteChangeClassificationFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Could not classify persistent-store change; reconciling defensively: \(error.description)"
        }
    }
}
