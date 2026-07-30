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
        #expect(WhereLog.reporting.primaryScope.name == "reporting")
        #expect(WhereLog.reporting.primaryScope.parentID == rootID)
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

    @Test func theReadPathsSpanOnlyLeavesShareTheReportingGroup() {
        let reportingID = WhereLog.reporting.primaryScope.id
        for scope in [
            WhereLog.reporting(ReportReaderLog.self).primaryScope,
            WhereLog.reporting(DataIssueScannerLog.self).primaryScope,
            WhereLog.reporting(PresenceCalendarLog.self).primaryScope,
        ] {
            #expect(scope.parentID == reportingID)
        }
    }
}

// MARK: - Span names

/// Covers the span names that aren't just their Swift case name — the ones with
/// a payload, where reflection would leak the module into recorded history.
struct WhereLogSpanNameTests {
    @Test func detectorSpansAreNamedAfterTheCategoryTheyScanFor() {
        #expect(
            String(describing: DataIssueScannerLog.SpanName.detect(.missingDays))
                == "detect(missing-days)",
        )
        #expect(
            String(describing: DataIssueScannerLog.SpanName.detect(.borderDrift))
                == "detect(border-drift)",
        )
        #expect(String(describing: DataIssueScannerLog.SpanName.scan) == "scan")
    }

    @Test func everyCategoryHasAHyphenatedNameOfItsOwn() {
        // A new category must earn a name rather than inherit one — duplicates
        // would pool two detectors' timings under one span.
        let names = DataIssueCategory.allCases.map(\.name)
        #expect(Set(names).count == DataIssueCategory.allCases.count)
        #expect(names.allSatisfy { !$0.isEmpty && $0 == $0.lowercased() })
    }

    @Test func detectorsDeclareTheCategoryTheyDetect() {
        #expect(MissingDaysDetector().detects == .missingDays)
        #expect(BorderDriftDetector().detects == .borderDrift)
        #expect(AbruptLocationChangeDetector().detects == .abruptChange)
        #expect(FlightDayDetector().detects == .flightDay)
    }
}

// MARK: - Event rendering

/// Spot-checks representative collaborator events: rendered message, severity,
/// stable persisted name, and `externalID` correlation.
struct WhereLogEventTests {
    @Test func dayJournalStampsTheAffectedDayAsExternalID() {
        // externalIDs are the canonical store:// identities (see WhereStoreIDTests
        // for the exact URL strings), so inspect-by-object shares the store's keys.
        #expect(DayJournalLog.addedManualDay(day: "2026-06-05", regionCount: 2)
            .externalID == WhereStoreID.day("2026-06-05"))
        #expect(DayJournalLog.clearedYear(year: 2025).externalID == WhereStoreID.year(2025))
        #expect(DayJournalLog.wroteEvidence(id: "abc", hasBlob: true)
            .externalID == WhereStoreID.evidence("abc"))
        #expect(DayJournalLog.erasedAllData.externalID == nil)
        #expect(DayJournalLog.addedManualDay(day: "d", regionCount: 2).level == .info)
    }

    @Test func swiftDataStoreCorruptionIsAFault() {
        #expect(SwiftDataStoreLog.droppedCorruptRecord(type: "SDEvidence").level == .fault)
        #expect(SwiftDataStoreLog.openedInMemory(mode: "inMemory").level == .info)
        #expect(
            SwiftDataStoreLog.ignoredUnknownTrackedRegions(ids: ["zz"]).level == .warning,
        )
        #expect(
            SwiftDataStoreLog.ignoredUnknownTrackedRegions(ids: ["us-CA", "us-NY"])
                .message.contains("us-CA, us-NY"),
        )
    }

    @Test func locationIngestorTracesSampleFailuresByID() {
        #expect(
            LocationIngestorLog.persistFailed(sampleID: "abc", description: "x")
                .externalID == WhereStoreID.sample("abc"),
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
