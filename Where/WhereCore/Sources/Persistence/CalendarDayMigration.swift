import Foundation
import LogKit
import SwiftData

/// Backfills the timezone-independent `CalendarDay` identity onto records that
/// predate it.
///
/// Manual-day rows written before the `CalendarDay` cutover keyed off an
/// absolute `dateKey` instant (midnight in the writer's zone); dismissal keys
/// embedded that instant as Unix seconds. Both drift onto a different logical day
/// when the device changes time zones. This migration:
///
/// 1. Sets `SDManualDay.dayKey` (ISO `YYYY-MM-DD`) from the legacy `dateKey`,
///    recovering the day the instant *meant* regardless of the writer's zone
///    (see `CalendarDay.init(recoveringLegacyStartOfDay:in:)`).
/// 2. Rewrites legacy epoch-keyed `SDDismissedIssue.key`s (`prefix:<epoch>`) to
///    the calendar-day form (`prefix:<YYYY-MM-DD>`) matching the new
///    `DataIssueID.storageKey`.
///
/// Both are in-place column edits (no inserts/deletes), and each step skips rows
/// that already carry the new form, so the migration is idempotent.
struct CalendarDayMigration: StoreMigration {
    let version = 1
    let name = "Backfill CalendarDay keys"

    private static let logger = WhereLog.channel(.swiftDataStore)

    func migrate(_ context: ModelContext, calendar: Calendar) throws {
        try backfillManualDayKeys(context, calendar: calendar)
        try rewriteDismissedIssueKeys(context, calendar: calendar)
    }

    private func backfillManualDayKeys(_ context: ModelContext, calendar: Calendar) throws {
        let rows = try context.fetch(FetchDescriptor<SDManualDay>())
        var migrated = 0
        for row in rows where row.dayKey == nil {
            guard let dateKey = row.dateKey else { continue }
            row.dayKey = CalendarDay(recoveringLegacyStartOfDay: dateKey, in: calendar).description
            migrated += 1
        }
        if migrated > 0 {
            Self.logger.info("CalendarDay migration: backfilled \(migrated) manual day key(s)")
        }
    }

    private func rewriteDismissedIssueKeys(_ context: ModelContext, calendar: Calendar) throws {
        let rows = try context.fetch(FetchDescriptor<SDDismissedIssue>())
        var migrated = 0
        for row in rows {
            guard let key = row.key,
                  let rewritten = Self.rewriteLegacyIssueKey(key, calendar: calendar)
            else { continue }
            row.key = rewritten
            migrated += 1
        }
        if migrated > 0 {
            Self.logger.info("CalendarDay migration: rewrote \(migrated) dismissed-issue key(s)")
        }
    }

    /// Convert a legacy dismissal key whose day fields are Unix-second instants
    /// (`borderDrift:1712001600`) to the calendar-day form
    /// (`borderDrift:2026-04-01`). Returns `nil` when the key is already in the
    /// new form or isn't recognized, so re-running never double-rewrites.
    static func rewriteLegacyIssueKey(_ key: String, calendar: Calendar) -> String? {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        let dayFields = Array(parts.dropFirst())
        // Already calendar-day form (fields contain a "-") → nothing to do.
        guard dayFields.allSatisfy({ !$0.contains("-") }) else { return nil }

        var converted: [String] = []
        for field in dayFields {
            guard let epoch = Double(field) else { return nil }
            let day = CalendarDay(
                recoveringLegacyStartOfDay: Date(timeIntervalSince1970: epoch),
                in: calendar,
            )
            converted.append(day.description)
        }
        return ([parts[0]] + converted).joined(separator: ":")
    }
}
