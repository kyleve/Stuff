import Foundation

/// The pure read path over user-attached `Evidence`, parallel to `ReportReader`
/// for day/region reports. Turns the store's `capturedAt`-indexed evidence into
/// the per-year list, per-day keys, and attachment bytes the evidence viewer and
/// the calendar day badge consume.
///
/// Reads only — evidence *writes* go through `DayJournal.addEvidence`. Holds no
/// mutable state (just the store + the calendar policy), so it's a cheap
/// `Sendable` value each collaborator that needs reads can keep its own copy of.
public struct EvidenceReader: Sendable {
    let store: any WhereStore
    let aggregator: DayAggregator

    /// Every piece of evidence captured in `year`, sorted ascending by
    /// `capturedAt` (the store's sort order).
    public func list(for year: Int) async throws -> [Evidence] {
        try await store.evidence(in: aggregator.yearInterval(year: year))
    }

    /// Calendar days (in the aggregator's calendar, matching `report.days`) for
    /// every day in `year` that carries at least one piece of evidence. Powers
    /// the calendar day badge.
    public func dayKeys(for year: Int) async throws -> Set<CalendarDay> {
        let evidence = try await store.evidence(in: aggregator.yearInterval(year: year))
        return Set(evidence.map { CalendarDay(from: $0.capturedAt, in: aggregator.calendar) })
    }

    /// The attachment bytes for a single evidence record, or `nil` when it has
    /// no stored blob.
    public func blob(for id: UUID) async throws -> Data? {
        try await store.evidenceBlob(for: id)
    }
}
