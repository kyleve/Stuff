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
        @LogField("mode", exposure: .restricted, kind: .technicalState) var mode: String
        var message: String {
            "Opened SwiftData store (mode: \(mode))"
        }
    }

    @LogEvent("opened-on-disk")
    struct OpenedOnDisk {
        @LogField("mode", exposure: .restricted, kind: .technicalState) var mode: String
        @LogField("app_group_resolved", exposure: .shareable, kind: .boolean)
        var appGroupResolved: Bool
        @LogField("url", exposure: .restricted, kind: .pathOrURL) var url: String
        var message: String {
            "Opened SwiftData store (mode: \(mode), appGroupResolved: "
                + "\(appGroupResolved), url: \(url))"
        }
    }

    @LogEvent("ignored-unknown-tracked-regions", level: .warning)
    struct IgnoredUnknownTrackedRegions {
        @LogField("ids", exposure: .restricted, kind: .location) var ids: [String]
        @LogField("unknown_region_count", exposure: .shareable, kind: .count)
        var unknownRegionCount: Int
        var message: String {
            "Ignored \(ids.count) unknown tracked-region id(s): \(ids.joined(separator: ", "))"
        }
    }

    @LogEvent("ignored-unknown-primary-regions", level: .warning)
    struct IgnoredUnknownPrimaryRegions {
        @LogField("ids", exposure: .restricted, kind: .location) var ids: [String]
        @LogField("unknown_region_count", exposure: .shareable, kind: .count)
        var unknownRegionCount: Int
        var message: String {
            "Ignored \(ids.count) unknown primary-region id(s): \(ids.joined(separator: ", "))"
        }
    }

    @LogEvent("dropped-corrupt-record", level: .fault)
    struct DroppedCorruptRecord {
        @LogField("type", exposure: .restricted, kind: .technicalState) var type: String
        var message: String {
            "Dropped corrupt SwiftData record of type \(type)"
        }
    }

    @LogEvent("resolved-conflicting-immutable-records", level: .fault)
    struct ResolvedConflictingImmutableRecords {
        @LogField("type", exposure: .restricted, kind: .technicalState) var type: String
        @LogField("id", exposure: .restricted, kind: .identifier) var id: String
        @LogField("conflict_count", exposure: .shareable, kind: .count) var count: Int
        var message: String {
            "Resolved \(count) conflicting immutable \(type) records for id \(id)"
        }
    }

    @LogEvent("remote-change-classification-failed", level: .warning)
    struct RemoteChangeClassificationFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Could not classify persistent-store change; reconciling defensively: \(description)"
        }
    }
}
