import Foundation
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct RecordingCalendarEditorModelTests {
    @Test func differentHistoricalZonesCanBeReviewedOnePeriodAtATime() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture(unresolved: true)
        try await fixture.add([RecordingReviewTestSupport.sample(
            deviceID: RecordingReviewTestSupport.first,
            seconds: 1200.5,
        )])
        let periods = try [
            RecordingPeriod(
                start: RecordingReviewTestSupport.date(0),
                end: RecordingReviewTestSupport.date(1),
            ),
            RecordingPeriod(
                start: RecordingReviewTestSupport.date(1200),
                end: RecordingReviewTestSupport.date(1201),
            ),
        ]
        let first = RecordingCalendarEditorModel(
            services: fixture.services,
            periods: periods,
            devices: [RecordingReviewTestSupport.first],
            names: [:],
            selectedDevice: RecordingReviewTestSupport.first,
        )
        first.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        first.periods[1].isIncluded = false
        await first.review()
        #expect(first.canApply)
        #expect(first.reviewedRecovery?.segments.map(\.period) == [periods[0]])
        await first.apply()
        #expect(first.controls.didApply)
        let second = RecordingCalendarEditorModel(
            services: fixture.services,
            periods: periods,
            devices: [RecordingReviewTestSupport.first],
            names: [:],
            selectedDevice: RecordingReviewTestSupport.first,
        )
        second.timeZone = .gmt
        second.periods[0].isIncluded = false
        second.periods[1].isIncluded = false
        #expect(throws: RecordingCalendarEditorModel.DraftError.noPeriods) {
            try second.draft.get()
        }
        second.periods[1].isIncluded = true
        await second.review()
        await second.apply()
        #expect(second.controls.didApply)
        let controls = try await fixture.controls()
        let samples = try await fixture.store.allSamples()
        let selected = samples.filter { $0.recordingDeviceID == RecordingReviewTestSupport.first }
            .sorted { $0.timestamp < $1.timestamp }
        let assignments = try selected.map {
            try RecordingCalendarResolver.assignment(
                for: $0,
                decisions: controls.calendarContexts,
                version: RecordingEvidencePolicy.version,
            )
        }
        guard case let .resolved(firstDay) = assignments[0],
              case let .resolved(lastDay) = assignments[2]
        else {
            Issue.record("Each selected period needs its own confirmed calendar context"); return
        }
        #expect(firstDay.day == CalendarDay(year: 2025, month: 12, day: 31))
        #expect(lastDay.day == RecordingReviewTestSupport.day)
        #expect(assignments[1] == .unresolved)
        #expect(selected[0].recordingDay == .unresolved)
    }

    @Test func aZoneAndDeviceMustBeExplicitBeforeReview() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture(unresolved: true)
        let model = RecordingCalendarEditorModel(
            services: fixture.services,
            periods: fixture.periods,
            devices: [RecordingReviewTestSupport.first],
            names: [:],
            selectedDevice: nil,
        )
        #expect(model.timeZone == nil)
        #expect(throws: RecordingCalendarEditorModel.DraftError.missingDevice) {
            try model.draft.get()
        }
        model.deviceID = RecordingReviewTestSupport.first
        #expect(throws: RecordingCalendarEditorModel.DraftError.missingTimeZone) {
            try model.draft.get()
        }
        await model.review()
        #expect(try await fixture.controls().records.isEmpty)
        #expect(!model.canApply)
        model.timeZone = .gmt
        await model.review()
        #expect(model.canApply)
        #expect(try await fixture.controls().records.isEmpty)
    }

    @Test func anEditedDraftCannotSaveOrRetryAnOlderReview() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture(unresolved: true)
        let model = RecordingCalendarEditorModel(
            services: fixture.services,
            periods: fixture.periods,
            devices: [RecordingReviewTestSupport.first],
            names: [:],
            selectedDevice: RecordingReviewTestSupport.first,
        )
        model.timeZone = .gmt
        await model.review()
        model.periods[0].interval.end = RecordingReviewTestSupport.date(600)
        #expect(!model.canApply)
        #expect(model.reviewedRecovery == nil)
        await model.apply()
        #expect(try await fixture.controls().records.isEmpty)
        await model.review()
        model.controls.setBeforePublicationForTesting {
            throw RecordingReviewTestSupport.TestFailure.interruptedSaveReceipt
        }
        await model.apply()
        #expect(model.canRetry)
        model.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        #expect(!model.canRetry)
        await model.retry()
        #expect(try await fixture.controls().calendarContexts.count == 1)
    }

    @Test func changingTheDraftDuringReviewCannotEnableItsOldProposal() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture(unresolved: true)
        let model = RecordingCalendarEditorModel(
            services: fixture.services,
            periods: fixture.periods,
            devices: [RecordingReviewTestSupport.first, RecordingReviewTestSupport.second],
            names: [:],
            selectedDevice: RecordingReviewTestSupport.first,
        )
        model.timeZone = .gmt
        let hold = ResolutionScanSuspension()
        model.controls.setBeforePublicationForTesting { await hold.suspendFirst() }
        let review = Task { await model.review() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        model.deviceID = RecordingReviewTestSupport.second
        hold.resume()
        await review.value
        #expect(!model.canApply)
        #expect(model.reviewedRecovery == nil)
        await model.apply()
        #expect(try await fixture.controls().records.isEmpty)
    }

    @Test func separatePeriodsKeepTheGapUnconfirmedAndRawObservationsUnchanged() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture(unresolved: true)
        let original = try await fixture.store.allSamples()
        let periods = try [
            RecordingPeriod(
                start: RecordingReviewTestSupport.date(0),
                end: RecordingReviewTestSupport.date(1),
            ),
            RecordingPeriod(
                start: RecordingReviewTestSupport.date(1200),
                end: RecordingReviewTestSupport.date(1201),
            ),
        ]
        let model = RecordingCalendarEditorModel(
            services: fixture.services,
            periods: periods,
            devices: [RecordingReviewTestSupport.first],
            names: [:],
            selectedDevice: RecordingReviewTestSupport.first,
        )
        model.timeZone = .gmt
        await model.review()
        #expect(model.reviewedRecovery?.segments.map(\.period) == periods)
        await model.apply()
        let controls = try await fixture.controls()
        let middle = try #require(original.first {
            $0.recordingDeviceID == RecordingReviewTestSupport.first &&
                $0.timestamp == RecordingReviewTestSupport.date(600)
        })
        #expect(try RecordingCalendarResolver.assignment(
            for: middle,
            decisions: controls.calendarContexts,
            version: RecordingEvidencePolicy.version,
        ) == .unresolved)
        #expect(try await Set(fixture.store.allSamples()) == Set(original))
    }
}
