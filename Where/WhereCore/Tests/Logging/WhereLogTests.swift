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
        #expect(DayJournalLog.AddedManualDay(
            day: .restricted(.dateTime, "2026-06-05"),
            regionCount: .shared(.count, 2),
        )
        .externalID == WhereStoreID.day("2026-06-05"))
        #expect(DayJournalLog.ClearedYear(
            year: .restricted(.domainValue, 2025),
        ).externalID == WhereStoreID.year(2025))
        #expect(DayJournalLog.WroteEvidence(
            id: .restricted(.identifier, "abc"),
            hasBlob: .shared(.boolean, true),
        )
        .externalID == WhereStoreID.evidence("abc"))
        #expect(DayJournalLog.ErasedAllData().externalID == nil)
        #expect(DayJournalLog.AddedManualDay(
            day: .restricted(.dateTime, "d"),
            regionCount: .shared(.count, 2),
        ).level == .info)
    }

    @Test func swiftDataStoreCorruptionIsAFault() {
        #expect(SwiftDataStoreLog.DroppedCorruptRecord(
            type: .restricted(.technicalState, "SDEvidence"),
        ).level == .fault)
        #expect(SwiftDataStoreLog.OpenedInMemory(
            mode: .restricted(.technicalState, "inMemory"),
        ).level == .info)
        #expect(
            SwiftDataStoreLog.IgnoredUnknownTrackedRegions(
                ids: .restricted(.location, ["zz"]),
                unknownRegionCount: .shared(.count, 1),
            ).level == .warning,
        )
        #expect(
            SwiftDataStoreLog.IgnoredUnknownTrackedRegions(
                ids: .restricted(.location, ["us-CA", "us-NY"]),
                unknownRegionCount: .shared(.count, 2),
            )
            .message.contains("us-CA, us-NY"),
        )
    }

    @Test func locationIngestorTracesSampleFailuresByID() {
        #expect(
            LocationIngestorLog.PersistFailed(
                sampleID: .restricted(.identifier, "abc"),
                description: .restricted(.errorDetails, "x"),
            )
            .externalID == WhereStoreID.sample("abc"),
        )
        #expect(LocationIngestorLog.PersistFailed(
            sampleID: .restricted(.identifier, "abc"),
            description: .restricted(.errorDetails, "x"),
        )
        .level == .error)
        #expect(LocationIngestorLog.MonitoringStarted().externalID == nil)
    }

    @Test func schedulerAuthorizationOutcomesUseHonestLevels() {
        #expect(LoggingReminderSchedulerLog.AuthorizationNotGranted().level == .warning)
        #expect(
            LoggingReminderSchedulerLog.AuthorizationRequestFailed(
                description: .restricted(.errorDetails, "x"),
            )
            .level == .error,
        )
        #expect(LoggingReminderSchedulerLog.Reconciled(
            scheduled: .shared(.count, 1),
            removed: .shared(.count, 0),
            badge: .shared(.count, 2),
        )
        .level == .info)
    }

    @Test func widgetRefresherKeepsItsHistoricalEventName() {
        #expect(WidgetTimelineRefresherLog.scopeName == "WidgetRefresher")
    }
}
