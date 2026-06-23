import Foundation

/// One persisted row, reduced to display strings keyed by column name. A column
/// missing from `cells` had no stored value for this row.
struct InspectorRow: Identifiable {
    /// Position within the fetched page; stable for the lifetime of a `rows(for:)`
    /// result, which is all the list diffing needs.
    let id: Int
    let cells: [String: String]
}

/// The result of loading an entity's rows: the page of rows plus enough context
/// for the detail view to say whether it is showing everything.
struct InspectorRowSet {
    let rows: [InspectorRow]
    /// Total persisted rows for the entity (may exceed `rows.count`).
    let totalCount: Int
    /// `true` when `rowLimit` capped the page below `totalCount`.
    let isTruncated: Bool
}
