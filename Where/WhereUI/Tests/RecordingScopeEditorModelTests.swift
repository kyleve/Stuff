import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct RecordingScopeEditorModelTests {
    @Test func separateRangesStaySeparateUntilTheUserChangesTheirBounds() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let periods = try [
            RecordingPeriod(
                start: RecordingReviewTestSupport.date(0),
                end: RecordingReviewTestSupport.date(100),
            ),
            RecordingPeriod(
                start: RecordingReviewTestSupport.date(1100),
                end: RecordingReviewTestSupport.date(1201),
            ),
        ]
        let choice = RecordingChoiceModel(services: fixture.services, periods: periods)
        await choice.load()
        await choice.choose(.select(RecordingReviewTestSupport.first))
        let editor = try RecordingScopeEditorModel(
            presentation: #require(choice.presentation),
            originalPeriods: periods,
        )
        #expect(try editor.request.get().scope == .periods(periods))
        guard case let .periods(intervals) = editor.draft
        else { Issue.record("Expected interval draft"); return }
        intervals[0].end = intervals[0].start
        #expect(throws: RecordingPeriod.ValidationError.self) { try editor.request.get() }
        intervals[0].end = RecordingReviewTestSupport.date(200)
        let edited = try editor.request.get()
        guard case let .periods(updated) = edited.scope
        else { Issue.record("Expected intervals"); return }
        #expect(updated.count == 2)
        #expect(updated[0].end == RecordingReviewTestSupport.date(200))
        #expect(updated[1] == periods[1])
        #expect(try await fixture.controls().sourceChoices.isEmpty)
        await choice.review(edited)
        #expect(try RecordingReviewTestSupport.preview(choice).proposal.decision.periods == updated)
        await choice.apply()
        #expect(try await fixture.controls().sourceChoices.first?.periods == updated)
    }

    @Test func unassignedDayNeedsExplicitDateInputAndCoreCalendarCoverage() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture(unresolved: true)
        let choice = RecordingChoiceModel(services: fixture.services, periods: fixture.periods)
        await choice.load()
        await choice.choose(.select(RecordingReviewTestSupport.first))
        let editor = try RecordingScopeEditorModel(
            presentation: #require(choice.presentation),
            originalPeriods: fixture.periods,
        )
        editor.kind = .recordingDay
        guard case let .recordingDay(day) = editor.draft
        else { Issue.record("Expected logical day draft"); return }
        #expect(day.needsDateConfirmation)
        #expect(throws: RecordingScopeEditorModel.DraftError.self) { try editor.request.get() }
        // A date skipped in one zone must remain expressible as a logical date in this editor.
        let skipped = CalendarDay(year: 2011, month: 12, day: 30)
        day.date = skipped.startOfDay(in: RecordingScopeEditorModel.pickerCalendar)
        let request = try editor.request.get()
        #expect(request.scope == .recordingDay(
            deviceID: RecordingReviewTestSupport.first,
            day: skipped,
        ))
        await choice.review(request)
        guard case .needsCalendarContext = choice.inspection
        else { Issue.record("Coverage must not be inferred from picker input"); return }
        #expect(!choice.canApply)
        await choice.useOriginalPeriods()
        #expect(choice.canApply)
        #expect(try RecordingReviewTestSupport.preview(choice).proposal.decision.periods == fixture
            .periods)
        #expect(try await fixture.controls().calendarContexts.isEmpty)
    }

    @Test func automaticWholeDayRequiresAnExplicitDeviceAndKeepsTheAction() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let choice = RecordingChoiceModel(services: fixture.services, periods: fixture.periods)
        await choice.load()
        await choice.choose(.automatic)
        let editor = try RecordingScopeEditorModel(
            presentation: RecordingChoicePresentation(
                inspection: #require(choice.inspection),
                names: [:],
            ),
            originalPeriods: fixture.periods,
        )
        #expect(Set(editor.devices) == [
            RecordingReviewTestSupport.first,
            RecordingReviewTestSupport.second,
        ])
        editor.kind = .recordingDay
        #expect(throws: RecordingScopeEditorModel.DraftError.self) { try editor.request.get() }
        guard case let .recordingDay(day) = editor.draft
        else { Issue.record("Expected day"); return }
        day.deviceID = RecordingReviewTestSupport.second
        let request = try editor.request.get()
        #expect(request.action == .automatic)
        #expect(request.scope == .recordingDay(
            deviceID: RecordingReviewTestSupport.second,
            day: RecordingReviewTestSupport.day,
        ))
    }
}
