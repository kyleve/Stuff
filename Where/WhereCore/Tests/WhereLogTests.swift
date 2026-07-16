import PeriscopeCore
import Testing
@testable import WhereCore

// MARK: - Periscope log tree

/// Covers `WhereLog`'s Periscope scope tree: the `"Where"` root, the grouping
/// scopes, and that collaborator leaves descend from the right parent.
struct WhereLogTreeTests {
    @Test func rootScopeIsWhere() {
        #expect(WhereLog.root.primaryScope.name == "Where")
    }

    @Test func groupScopesDescendFromTheRoot() {
        let rootID = WhereLog.root.primaryScope.id
        #expect(WhereLog.location.primaryScope.name == "location")
        #expect(WhereLog.location.primaryScope.parentID == rootID)
        #expect(WhereLog.reminders.primaryScope.name == "reminders")
        #expect(WhereLog.reminders.primaryScope.parentID == rootID)
        #expect(WhereLog.backup.primaryScope.name == "backup")
        #expect(WhereLog.widgets.primaryScope.name == "widgets")
        #expect(WhereLog.session.primaryScope.name == "session")
        #expect(WhereLog.evidence.primaryScope.name == "evidence")
        #expect(WhereLog.recentActivity.primaryScope.name == "recentActivity")
    }

    @Test func collaboratorLeavesDescendFromTheirGroup() {
        let ingestor = WhereLog.location(LocationIngestorLog.self)
        #expect(ingestor.primaryScope.name == "LocationIngestor")
        #expect(ingestor.primaryScope.parentID == WhereLog.location.primaryScope.id)
    }

    @Test func directLeavesDescendFromTheRoot() {
        let store = WhereLog.root(SwiftDataStoreLog.self)
        #expect(store.primaryScope.name == "SwiftDataStore")
        #expect(store.primaryScope.parentID == WhereLog.root.primaryScope.id)
    }
}

// MARK: - Event rendering

/// Spot-checks representative collaborator events: rendered message, severity,
/// stable persisted name, and `externalID` correlation.
struct WhereLogEventTests {
    @Test func dayJournalStampsTheAffectedDayAsExternalID() {
        #expect(DayJournalLog.addedManualDay(day: "2026-06-05", regionCount: 2)
            .externalID == "2026-06-05")
        #expect(DayJournalLog.clearedYear(year: 2025).externalID == "2025")
        #expect(DayJournalLog.erasedAllData.externalID == nil)
        #expect(DayJournalLog.addedManualDay(day: "d", regionCount: 2).level == .info)
    }

    @Test func swiftDataStoreCorruptionIsAFault() {
        #expect(SwiftDataStoreLog.droppedCorruptRecord(type: "SDEvidence").level == .fault)
        #expect(SwiftDataStoreLog.openedInMemory(mode: "inMemory").level == .info)
        #expect(
            SwiftDataStoreLog.ignoredUnknownTrackedRegions(count: 1, ids: "zz").level == .warning,
        )
    }

    @Test func locationIngestorTracesSampleFailuresByID() {
        #expect(
            LocationIngestorLog.persistFailed(sampleID: "abc", description: "x")
                .externalID == "abc",
        )
        #expect(LocationIngestorLog.persistFailed(sampleID: "abc", description: "x")
            .level == .error)
        #expect(LocationIngestorLog.monitoringStarted.externalID == nil)
    }

    @Test func schedulerAuthorizationOutcomesUseHonestLevels() {
        #expect(LoggingReminderSchedulerLog.authorizationNotGranted.level == .warning)
        #expect(
            LoggingReminderSchedulerLog.authorizationRequestFailed(description: "x")
                .level == .error,
        )
        #expect(LoggingReminderSchedulerLog.reconciled(scheduled: 1, removed: 0, badge: 2)
            .level == .info)
    }

    @Test func widgetRefresherKeepsItsHistoricalEventName() {
        #expect(WidgetTimelineRefresherLog.eventName == "WidgetRefresher")
    }
}
