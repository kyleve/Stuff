import Foundation

/// Canonical `store://` identities for the Where store's object families,
/// vended as the string form used for Periscope `LogEvent.externalID`s. Keying
/// a log event's `externalID` on the same identity the store and backups use
/// lets the log tooling's inspect-by-object pull every event about one row
/// (a day, a year, an evidence item, a GPS sample) under one namespaced,
/// collision-free key — a bare `"2025"` year and an evidence UUID can't clash
/// the way flat strings in one index could.
///
/// Mirrors ``DataIssueID``'s use of ``StoreURL`` (`store://issues/…`), which is
/// the typed exemplar: a value with a persisted identity conforms to
/// ``WhereStoreURLCodable`` and vends its own `storeURL`. These families don't
/// have (or don't yet need) a dedicated identity type, so their identity lives
/// here instead. Each is a single-identity object, so the identifying value
/// sits in the URL's `type` position (`store://<collection>/<value>`); the
/// values are UUID strings, ISO `CalendarDay` strings, or years — all
/// path-safe.
///
/// RegionKit deliberately does **not** use this: it sits below WhereCore (must
/// not import app code) and its regions are a bundled catalog, not store rows,
/// so `RegionAttributorLog` keeps its bare, already-stable catalog id as its
/// `externalID`.
public enum WhereStoreID {
    /// `store://days/<iso>` for a logical calendar day (its `CalendarDay`
    /// `description`, e.g. `2026-06-05`).
    public static func day(_ isoDay: String) -> String {
        StoreURL.url(collection: "days", type: isoDay, items: [:]).absoluteString
    }

    /// `store://years/<year>` for a whole year's data/scope (no `SDYear` row
    /// backs it — it's the synthetic identity the year-scoped reads share).
    public static func year(_ year: Int) -> String {
        StoreURL.url(collection: "years", type: String(year), items: [:]).absoluteString
    }

    /// `store://evidence/<id>` for an `Evidence` row (its `id.uuidString`).
    public static func evidence(_ id: String) -> String {
        StoreURL.url(collection: "evidence", type: id, items: [:]).absoluteString
    }

    /// `store://samples/<id>` for a `LocationSample` (its `id.uuidString`).
    public static func sample(_ id: String) -> String {
        StoreURL.url(collection: "samples", type: id, items: [:]).absoluteString
    }
}
