import Foundation
import RegionKit

public enum DataIssueCategory: Sendable, Hashable, CaseIterable {
    case missingDays
    case borderDrift
    case abruptChange
    case flightDay
}

/// Closed set of fix shapes. The UI switches on this, so a new detector that
/// reuses a shape needs no UI change; a genuinely new fix shape adds a case
/// (the compiler then flags the UI switch).
public enum IssueResolution: Sendable, Hashable {
    case backfill(MissingDayRange)
    case relabelDay(day: DayPresence, suggestedRegions: Set<Region>, approximateMeters: Double?)
    case markTravelDay(earlier: DayPresence, later: DayPresence, suggestedRegions: Set<Region>)
    /// A day whose region set was polluted by cruise-speed GPS fixes crossing
    /// untracked geography (a flight). `keepRegions` are the endpoints/dwell
    /// regions to preserve; `removedRegions` are the fly-over-only regions the
    /// one-tap fix drops (applied as an authoritative `overrideDay(keepRegions)`).
    /// `peakSpeedKMH` is the fastest leg, for the detail view's copy.
    case correctFlightDay(
        day: DayPresence,
        keepRegions: Set<Region>,
        removedRegions: Set<Region>,
        peakSpeedKMH: Double,
    )
}

public enum DataIssueID: Hashable, Sendable, WhereStoreURLCodable {
    case missingDays(start: CalendarDay)
    case borderDrift(day: CalendarDay)
    case abruptChange(earlier: CalendarDay, later: CalendarDay)
    case flightDay(day: CalendarDay)

    private static let collection = "issues"

    /// Stable, device- and timezone-independent identity, encoded as a single
    /// `store://issues/<type>?<days>` URL for persisted dismissal, backup, and
    /// `ForEach`. Each day is its `CalendarDay` ISO string so a dismissal
    /// survives a time-zone change instead of drifting onto a different day (the
    /// reason dismissals used to reappear after travel). Caveat: the *key* is
    /// pinned to its `CalendarDay`, but a GPS-derived issue's day is itself
    /// re-bucketed at read time, so a GPS-only dismissal can still shift with the
    /// underlying day — see the `CalendarDay` scope boundary in
    /// `WhereCore/AGENTS.md`.
    public var storeURL: URL {
        switch self {
            case let .missingDays(start):
                StoreURL.url(
                    collection: Self.collection,
                    type: "missingDays",
                    items: ["start": start.description],
                )
            case let .borderDrift(day):
                StoreURL.url(
                    collection: Self.collection,
                    type: "borderDrift",
                    items: ["day": day.description],
                )
            case let .abruptChange(earlier, later):
                StoreURL.url(
                    collection: Self.collection,
                    type: "abruptChange",
                    items: ["earlier": earlier.description, "later": later.description],
                )
            case let .flightDay(day):
                StoreURL.url(
                    collection: Self.collection,
                    type: "flightDay",
                    items: ["day": day.description],
                )
        }
    }

    public init?(storeURL url: URL) {
        guard let parts = StoreURL.parts(of: url), parts.collection == Self.collection else {
            return nil
        }
        switch parts.type {
            case "missingDays":
                guard let start = parts.value("start").flatMap(CalendarDay.init(iso:)) else {
                    return nil
                }
                self = .missingDays(start: start)
            case "borderDrift":
                guard let day = parts.value("day").flatMap(CalendarDay.init(iso:)) else {
                    return nil
                }
                self = .borderDrift(day: day)
            case "abruptChange":
                guard let earlier = parts.value("earlier").flatMap(CalendarDay.init(iso:)),
                      let later = parts.value("later").flatMap(CalendarDay.init(iso:))
                else {
                    return nil
                }
                self = .abruptChange(earlier: earlier, later: later)
            case "flightDay":
                guard let day = parts.value("day").flatMap(CalendarDay.init(iso:)) else {
                    return nil
                }
                self = .flightDay(day: day)
            default:
                return nil
        }
    }
}

public protocol DataIssue: Identifiable, Sendable where ID == DataIssueID {
    var id: DataIssueID { get }
    var category: DataIssueCategory { get }
    var sortKey: CalendarDay { get }
    var isDismissible: Bool { get }
    var resolution: IssueResolution { get }
}

public enum DriftThreshold: Int, CaseIterable, Sendable, Hashable {
    case km1 = 1000
    case km5 = 5000
    case km10 = 10000
    case km25 = 25000
    case km50 = 50000

    public var meters: Double {
        Double(rawValue)
    }

    public static let `default` = DriftThreshold.km1
}
