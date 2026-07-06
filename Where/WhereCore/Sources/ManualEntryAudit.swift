import Foundation

/// Audit metadata attached to a user-made manual day entry (a backfill or an
/// authoritative override), retained so a residency/day-count audit can later
/// answer *when* the correction was made, *why* (the note), and *where the
/// device physically was* at the time.
///
/// This describes the *act of making the entry*, not the day it corrects — the
/// day and its regions live on `DayPresence`. `note` and `location` are each
/// independently optional: the user may leave the reason blank, and a GPS fix
/// may be unobtainable (permission/timeout), in which case the audit still
/// honestly records `recordedAt` with a `nil` `location` rather than a faked
/// coordinate.
public struct ManualEntryAudit: Hashable, Sendable, Codable {
    /// When the manual entry was made (not the day it applies to).
    public let recordedAt: Date
    /// The user's free-text reason for the entry. `nil` (or empty) when none
    /// was given.
    public let note: String?
    /// Where the device was when the entry was made, when a fix was available.
    public let location: CapturedLocation?

    public init(recordedAt: Date, note: String?, location: CapturedLocation?) {
        self.recordedAt = recordedAt
        self.note = note
        self.location = location
    }
}

/// A GPS fix captured at a single moment — the "where were you when you made
/// this entry" half of `ManualEntryAudit`. Kept as a plain value type so the
/// model layer stays CoreLocation-free (see `Coordinate`).
public struct CapturedLocation: Hashable, Sendable, Codable {
    public let coordinate: Coordinate
    public let horizontalAccuracy: Double
    /// The timestamp reported by the location fix itself, which can differ
    /// slightly from `ManualEntryAudit.recordedAt`.
    public let timestamp: Date

    public init(coordinate: Coordinate, horizontalAccuracy: Double, timestamp: Date) {
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}
