import Foundation
import SwiftData

/// One persisted row, reduced to display strings keyed by column name. A column
/// missing from `cells` had no stored value for this row.
///
/// `Sendable` so a page assembled on the background reader actor can cross back
/// to the main actor — `PersistentIdentifier` is itself `Sendable`, so it is the
/// stable identity that survives pagination appends and lets the detail flow
/// re-fetch this exact model to resolve its relationships.
public struct InspectorRow: Identifiable, Hashable, Sendable {
    /// The model's persistent identity. Stable across fetches and contexts (for
    /// saved rows), so it both keys the list and lets the reader re-fetch the
    /// model to resolve relationships on demand.
    public let persistentID: PersistentIdentifier
    public let cells: [String: String]

    public var id: PersistentIdentifier {
        persistentID
    }
}

/// The result of loading one page of an entity's rows: the page plus enough
/// context for the detail view to size columns and decide whether more rows
/// remain to "load more".
public struct InspectorRowSet: Sendable {
    public let rows: [InspectorRow]
    /// Total persisted rows for the entity (may exceed the rows loaded so far).
    public let totalCount: Int
    /// `true` when the loaded prefix is shorter than `totalCount`, i.e. the table
    /// should offer "load more".
    public let isTruncated: Bool
    /// Longest cell string (in characters) seen per column across this page,
    /// computed on the reader so the view can size monospaced columns without
    /// re-scanning every cell on the main thread.
    public let columnCharacterCounts: [String: Int]
}

/// The resolved contents of one relationship, produced on the reader for the
/// detail drill-in: the destination entity's metadata (so the related rows can
/// be drilled into further) and the related rows themselves.
///
/// `Sendable` so it can cross from the reader actor back to the UI. `entity` is
/// `nil` when nothing resolved (an empty or unreadable relationship), in which
/// case `rows` is empty and the view shows an empty state.
public struct InspectorRelatedRows: Sendable {
    public let entity: InspectorEntity?
    public let rows: [InspectorRow]
    /// `true` for a to-many relationship (the UI lists the rows); `false` for a
    /// to-one (the UI drills straight into the single related row).
    public let isToMany: Bool
    /// How many rows the relationship references in total. `rows` is capped to the
    /// reader's `rowLimit`, so this may exceed `rows.count`; the UI notes the
    /// shortfall rather than silently showing a partial set.
    public let totalCount: Int
}
