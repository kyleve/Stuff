import Foundation

/// A request for a page of rows from a data source: opaque filters (validated
/// against the source's `filters` schema), an optional page size, and an opaque
/// cursor minted by the source.
public struct PortholeQuery: Sendable, Codable, Equatable {
    /// An `.object` of filter keys; validated against the source descriptor's
    /// `filters` schema before the source runs.
    public var filters: PortholeValue
    public var limit: Int?
    /// Opaque continuation token from a prior page's `nextCursor`.
    public var cursor: String?

    public init(filters: PortholeValue = .object([:]), limit: Int? = nil, cursor: String? = nil) {
        self.filters = filters
        self.limit = limit
        self.cursor = cursor
    }
}

/// One page of data-source results: the rows, a cursor for the next page (nil
/// when exhausted), and an optional total count (nil when counting is
/// expensive).
public struct PortholePage: Sendable, Codable, Equatable {
    public var rows: [PortholeValue]
    public var nextCursor: String?
    public var totalCount: Int?

    public init(rows: [PortholeValue], nextCursor: String? = nil, totalCount: Int? = nil) {
        self.rows = rows
        self.nextCursor = nextCursor
        self.totalCount = totalCount
    }
}
