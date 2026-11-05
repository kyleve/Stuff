import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct DataIssueScannerHistoryTests {
    @Test func oldRecordingWorkRemainsAfterYearRollover() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        try await LocationHistoryReaderTestSupport.add(
            HistoricalDataIssueTestSupport.conflicts(at: [-600, 0, 600]),
            to: store,
        )
        let scanner = HistoricalDataIssueTestSupport.scanner(store)
        let result = try await scanner.historicalScan(driftThresholdMeters: 1000, force: false)
        #expect(result.years.map(\.context.historicalYear) == [2000, 2001, 2002])
        #expect(result.recording.issues.count == 1)
        let annual = try await scanner.scan(
            year: 2001,
            primaryRegions: [],
            driftThresholdMeters: 1000,
            force: true,
        )
        let historical = try #require(result.years.first { $0.context.historicalYear == 2001 })
        #expect(historical.scan.issues.map(\.id) == annual.issues.map(\.id))
        #expect(historical.scan.completeness == annual.completeness)
        #expect(historical.scan.reviews == annual.reviews)
    }

    @Test func emptyHistoryStillIncludesTodaysMissingWork() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let result = try await HistoricalDataIssueTestSupport.scanner(store)
            .historicalScan(driftThresholdMeters: 1000, force: false)
        #expect(result.years.map(\.context.historicalYear) == [2002])
        #expect(result.recording.issues.isEmpty)
        #expect(result.issues.contains { $0.category == .missingDays })
    }

    @Test func lateHistoricalImportInvalidatesBothAnnualAndHistoricalCaches() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let scanner = HistoricalDataIssueTestSupport.scanner(store)
        let first = try await scanner.historicalScan(driftThresholdMeters: 1000, force: false)
        let annual = try await scanner.scan(
            year: 2002,
            primaryRegions: [],
            driftThresholdMeters: 1000,
            force: false,
        )
        let cached = try await scanner.historicalScan(driftThresholdMeters: 1000, force: false)
        #expect(cached.revision == first.revision)
        try await LocationHistoryReaderTestSupport.add(
            HistoricalDataIssueTestSupport.conflicts(at: [-86400, -85800]),
            to: store,
        )
        await scanner.invalidate()
        let updated = try await scanner.historicalScan(driftThresholdMeters: 1000, force: false)
        #expect(updated.revision != first.revision)
        #expect(updated.years.map(\.context.historicalYear) == [2000, 2002])
        #expect(updated.recording.issues.count == 1)
        let updatedAnnual = try await scanner.scan(
            year: 2002,
            primaryRegions: [],
            driftThresholdMeters: 1000,
            force: false,
        )
        #expect(updatedAnnual.revision != annual.revision)
    }

    @Test func calendarRecoveryNarrowsTheYearInventoryWithoutHidingAConflict() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let samples = try [0.0, 600].flatMap { seconds in
            try [
                LocationHistoryReaderTestSupport.sample(seconds: seconds, assignment: .unresolved),
                LocationHistoryReaderTestSupport.sample(
                    seconds: seconds,
                    deviceID: RecordingAssessmentTestSupport.second,
                    longitude: -74,
                    assignment: .unresolved,
                ),
            ]
        }
        try await LocationHistoryReaderTestSupport.add(samples, to: store)
        let scanner = HistoricalDataIssueTestSupport.scanner(store)
        let before = try await scanner.historicalScan(driftThresholdMeters: 1000, force: false)
        #expect(before.years.map(\.context.historicalYear) == [2000, 2001, 2002])
        let referenceSets = try before.recording.issues.map { try before.references(for: $0) }
        let queue = try RecordingReviewQueue(references: referenceSets.flatMap(\.self))
        for device in [
            RecordingAssessmentTestSupport.first,
            RecordingAssessmentTestSupport.second,
        ] {
            let decision = try RecordingCalendarDecision(
                id: .init(rawValue: UUID()),
                author: RecordingAssessmentTestSupport.first,
                deviceID: device,
                periods: [RecordingAssessmentTestSupport.period(0, 601)],
                action: .establish(.init(timeZone: .gmt, secondsFromGMT: 0)),
                predecessors: [],
                version: RecordingEvidencePolicy.version,
            )
            try await RecordingChoiceTestSupport.append(.calendar(decision), store: store)
        }
        await scanner.invalidate()
        let after = try await scanner.historicalScan(driftThresholdMeters: 1000, force: false)
        #expect(after.years.map(\.context.historicalYear) == [2001, 2002])
        #expect(after.recording.issues.count == 1)
        #expect(try await scanner.reassess(queue).count == 1)
        #expect(try await Set(store.allSamples()) == Set(samples))
    }

    @Test func newDayAndChangedSettingsRefreshTheHistoricalCache() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let clock = MutableClock(WhereCoreTestSupport.iso("2001-12-31T23:59:00Z"))
        let scanner = HistoricalDataIssueTestSupport.scanner(store, now: { clock.now })
        let first = try await scanner.historicalScan(driftThresholdMeters: 1000, force: false)
        clock.advance(by: 120)
        let next = try await scanner.historicalScan(driftThresholdMeters: 1000, force: false)
        #expect(next.revision != first.revision)
        #expect(next.years.map(\.context.historicalYear) == [2002])
        let changed = try await scanner.historicalScan(driftThresholdMeters: 2000, force: false)
        #expect(changed.revision != next.revision)
    }

    @Test func failedRefreshThrowsAndLeavesPreviouslyCapturedWorkIntact() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        try await LocationHistoryReaderTestSupport.add(
            LocationHistoryReaderTestSupport.competingTracks(),
            to: store,
        )
        let access = DataCompatibilityAccess(
            base: store,
            identity: .local(storeID: DataCompatibilityTestSupport.storeID),
            requiredMajor: 1,
            policy: RecordingChoiceTestSupport.policy,
            onFailure: { _, _ in },
        )
        let scanner = HistoricalDataIssueTestSupport.scanner(access.store)
        let before = try await scanner.historicalScan(driftThresholdMeters: 1000, force: false)
        access.revoke()
        await scanner.invalidate()
        await #expect(throws: DataAccessPermit.AccessError.revoked) {
            try await scanner.historicalScan(driftThresholdMeters: 1000, force: false)
        }
        #expect(before.recording.issues.count == 1)
        let issue = try #require(before.recording.issues.first)
        #expect(try before.references(for: issue).isEmpty == false)
    }

    @Test func resetWhileCompletionIsHeldCannotRestoreOldHistory() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        try await LocationHistoryReaderTestSupport.add(
            LocationHistoryReaderTestSupport.competingTracks(),
            to: store,
        )
        let scanner = HistoricalDataIssueTestSupport.scanner(store)
        let gate = CompatibilityTestGate()
        await scanner.setBeforeHistoricalPublicationForTesting { await gate.suspend() }
        let pending = Task {
            try await scanner.historicalScan(driftThresholdMeters: 1000, force: false)
        }
        await gate.waitUntilEntered()
        do {
            try await store.perform {
                _ = try await store.rotateDataGeneration(
                    reason: .accountReset,
                    changedBy: RecordingAssessmentTestSupport.first,
                    at: HistoricalDataIssueTestSupport.now,
                )
            }
        } catch {
            await gate.resume()
            _ = await pending.result
            throw error
        }
        await scanner.invalidate()
        await gate.resume()
        let result = try await pending.value
        #expect(result.recording.issues.isEmpty)
        #expect(try await result.recording.generationID == (store.dataGeneration().id))
        #expect(result.years.map(\.context.historicalYear) == [2002])
        let cached = try await scanner.historicalScan(driftThresholdMeters: 1000, force: false)
        #expect(cached.revision == result.revision)
    }

    @Test func cancellationAfterReadsDoesNotPublishOrPopulateTheCache() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let scanner = HistoricalDataIssueTestSupport.scanner(store)
        let gate = CompatibilityTestGate()
        await scanner.setBeforeHistoricalPublicationForTesting { await gate.suspend() }
        let pending = Task {
            try await scanner.historicalScan(driftThresholdMeters: 1000, force: false)
        }
        await gate.waitUntilEntered()
        pending.cancel()
        await gate.resume()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(await scanner.historicalCache == nil)
        let retry = try await scanner.historicalScan(driftThresholdMeters: 1000, force: false)
        #expect(retry.years.map(\.context.historicalYear) == [2002])
    }
}
