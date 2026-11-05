import Foundation
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct RecordingIgnoreEditorModelTests {
    @Test func anUnchangedEndKeepsItsSavedBoundaryWhenZoneRulesDiffer() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let original = try RecordingIgnoreDecision.Until(
            day: RecordingReviewTestSupport.day,
            timeZone: .gmt,
        )
        var wire = try #require(JSONSerialization
            .jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        // Simulate stored rules that differ from the current database, preserving the saved offset.
        wire["timeZone"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(zone),
            options: .fragmentsAllowed,
        )
        let saved = try JSONDecoder().decode(
            RecordingIgnoreDecision.Until.self,
            from: JSONSerialization.data(withJSONObject: wire),
        )
        let decision = try RecordingIgnoreDecision(
            id: .init(rawValue: UUID()),
            author: RecordingReviewTestSupport.first,
            deviceID: RecordingReviewTestSupport.first,
            periods: [.init(start: RecordingReviewTestSupport.date(0), end: saved.end)],
            change: .ignore(saved),
            predecessors: [],
            version: RecordingEvidencePolicy.version,
        )
        let model = try RecordingIgnoreEditorModel(
            services: fixture.services,
            name: "Phone One",
            intent: .changingEnd(decision),
        )
        guard case let .until(end) = model.draft,
              case let .ignoreEnd(edit) = try #require(model.edits.get().first)
        else { Issue.record("Expected an end-date edit"); return }
        #expect(edit.until == saved)
        #expect(try edit.until.end != (RecordingIgnoreDecision.Until(day: end.day, timeZone: zone))
            .end)
        end.day = .init(year: 2026, month: 1, day: 2)
        guard case let .ignoreEnd(changed) = try #require(model.edits.get().first)
        else { Issue.record("Expected an updated end-date edit"); return }
        #expect(changed.until.timeZone == zone)
        #expect(try changed.until == (RecordingIgnoreDecision.Until(day: end.day, timeZone: zone)))
    }

    @Test func aNewIgnoreKeepsItsCapturedStartZoneAndLogicalDay() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let model = try RecordingIgnoreEditorModel(
            services: fixture.services,
            name: "Phone Two",
            intent: .starting(
                deviceID: RecordingReviewTestSupport.second,
                at: RecordingReviewTestSupport.date(600),
                timeZone: zone,
            ),
        )
        guard case let .until(end) = model.draft
        else { Issue.record("Expected a date draft"); return }
        #expect(end.day == CalendarDay(year: 2025, month: 12, day: 31))
        #expect(end.timeZone == zone)
        end.date = CalendarDay(year: 2026, month: 1, day: 2)
            .startOfDay(in: RecordingScopeEditorModel.pickerCalendar)
        await model.review()
        #expect(model.canApply)
        let review = try #require(model.controls.state.review)
        let period = try #require(review.proposal.evidence.query.periods.first)
        #expect(period.start == RecordingReviewTestSupport.date(600))
        #expect(period.end == RecordingReviewTestSupport.date(2 * 86400 + 5 * 3600))
        #expect(try await fixture.controls().ignores.isEmpty)
        await model.apply()
        #expect(model.controls.didApply)
        #expect(try await fixture.controls().ignores.first?.deviceID == RecordingReviewTestSupport
            .second)
    }

    @Test func aChangedDateCannotApplyOrRetryThePreviousProposal() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = try RecordingIgnoreEditorModel(
            services: fixture.services,
            name: "Phone One",
            intent: .starting(
                deviceID: RecordingReviewTestSupport.first,
                at: RecordingReviewTestSupport.date(600),
                timeZone: .gmt,
            ),
        )
        guard case let .until(end) = model.draft
        else { Issue.record("Expected a date draft"); return }
        await model.review()
        end.day = .init(year: 2026, month: 1, day: 2)
        #expect(!model.canApply)
        #expect(model.inspection == nil)
        await model.apply()
        #expect(try await fixture.controls().records.isEmpty)
        await model.review()
        let proposal = try #require(model.controls.state.review?.proposal)
        model.controls.setBeforePublicationForTesting {
            throw RecordingReviewTestSupport.TestFailure.interruptedSaveReceipt
        }
        await model.apply()
        #expect(model.canRetry)
        end.day = .init(year: 2026, month: 1, day: 3)
        #expect(!model.canRetry)
        await model.retry()
        #expect(model.controls.state.review?.proposal == proposal)
        end.day = .init(year: 2026, month: 1, day: 2)
        model.controls.setBeforePublicationForTesting {}
        await model.retry()
        #expect(model.controls.didApply)
        #expect(try await fixture.controls().ignores.count == 1)
    }

    @Test func anExpandedResumeCanApplyOnlyAfterItsRefreshedInspection() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let original = try await RecordingIgnoreTestSupport.ignore(
            fixture: fixture,
            deviceID: RecordingReviewTestSupport.first,
            day: RecordingReviewTestSupport.day,
        )
        let model = try RecordingIgnoreEditorModel(
            services: fixture.services,
            name: "Phone One",
            intent: .resuming(original, at: RecordingReviewTestSupport.date(600)),
        )
        await model.review()
        let requested = try model.edits.get()
        let originalPreview = try #require(model.controls.state.review?.proposal)
        let coordinator = fixture.services.recordingControlEdits
        let extended = try await coordinator.review(.changingIgnoreEnd(
            of: original,
            until: .init(day: .init(year: 2026, month: 1, day: 3), timeZone: .gmt),
        ))
        #expect(try await coordinator.apply(extended) == .applied)
        await model.apply()
        let refreshed = try #require(model.controls.state.review)
        #expect(refreshed.refreshed)
        #expect(refreshed.requestedEdits == requested)
        #expect(refreshed.proposal.edits.map(\.edit) != requested)
        #expect(refreshed.proposal.evidence.query.periods != originalPreview.evidence.query.periods)
        let inspection = try #require(model.inspection).get()
        #expect(inspection.changes.last?.period.end == RecordingReviewTestSupport.date(3 * 86400))
        #expect(model.canApply)
        #expect(try await fixture.controls().ignores.count == 2)
        await model.apply()
        #expect(model.controls.didApply)
        #expect(try await fixture.controls().ignores.count == 3)
    }

    @Test func elapsedUndoStopsAtItsCapturedCutoff() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let original = try await RecordingIgnoreTestSupport.ignore(
            fixture: fixture,
            deviceID: RecordingReviewTestSupport.first,
            day: RecordingReviewTestSupport.day,
        )
        let period = try #require(original.periods.first)
        let model = try RecordingIgnoreEditorModel(
            services: fixture.services,
            name: "Phone One",
            intent: .restoringElapsed(
                deviceID: original.deviceID,
                period: period,
                before: RecordingReviewTestSupport.date(600),
            ),
        )
        await model.review()
        await model.apply()
        let history = try await fixture.services.recordingControlEdits
            .ignoreHistory(for: original.deviceID)
        #expect(history.segments.map(\.resolution) == [.eligible, .ignored])
        #expect(history.segments.first?.period.end == RecordingReviewTestSupport.date(600))
        #expect(throws: RecordingIgnoreEditorModel.DraftError.noElapsedPeriod) {
            try RecordingIgnoreEditorModel(
                services: fixture.services,
                name: "Phone One",
                intent: .restoringElapsed(
                    deviceID: original.deviceID,
                    period: period,
                    before: period.start,
                ),
            )
        }
    }

    @Test func draftChangesAndRetirementRejectLateOrQueuedReviews() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = try RecordingIgnoreEditorModel(
            services: fixture.services,
            name: "Phone One",
            intent: .starting(
                deviceID: RecordingReviewTestSupport.first,
                at: RecordingReviewTestSupport.date(600),
                timeZone: .gmt,
            ),
        )
        guard case let .until(end) = model.draft
        else { Issue.record("Expected a date draft"); return }
        let hold = ResolutionScanSuspension()
        model.controls.setBeforePublicationForTesting { await hold.suspendFirst() }
        let review = Task { await model.review() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        end.day = .init(year: 2026, month: 1, day: 2)
        hold.resume()
        await review.value
        #expect(!model.canApply)
        model.deactivate()
        await model.review()
        await model.apply()
        #expect(model.controls.state.review == nil)
        #expect(model.inspection == nil)
        #expect(try await fixture.controls().records.isEmpty)
    }
}
