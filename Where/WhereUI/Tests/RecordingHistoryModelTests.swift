import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct RecordingHistoryModelTests {
    @Test func strongAutomaticSelectionCanBeInspectedWithoutAnIssueOrWrite() async throws {
        let samples = try RecordingReviewTestSupport.strongMovementSamples()
        let fixture = try await RecordingReviewTestSupport.fixture(samples: samples)
        let model = RecordingHistoryModel(
            services: fixture.services,
            now: { RecordingReviewTestSupport.date(86400) },
        )
        model.inspect()
        let child = try #require(model.inspection?.model)
        await child.load()
        let preview = try RecordingReviewTestSupport.preview(child)
        #expect(preview.before.issues.isEmpty)
        #expect(preview.before.selections.flatMap(\.segments).contains {
            $0.resolution == .automatic(.movingOverStationary(RecordingReviewTestSupport.first))
        })
        #expect(child.selectedAction == nil)
        #expect(!child.canApply)
        #expect(try await fixture.controls().sourceChoices.isEmpty)
        #expect(try await Set(fixture.store.allSamples()) == Set(samples))
    }

    @Test func changingDraftDoesNotWidenAnOpenInspectionAndReplacementRetiresIt() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingHistoryModel(
            services: fixture.services,
            now: { RecordingReviewTestSupport.date(86400) },
        )
        model.inspect()
        let previous = try #require(model.inspection?.model)
        let original = previous.originalPeriods
        model.start = RecordingReviewTestSupport.date(-3600)
        #expect(previous.originalPeriods == original)
        model.inspect()
        let replacement = try #require(model.inspection?.model)
        #expect(replacement !== previous)
        #expect(replacement.originalPeriods.first?.start == model.start)
        await previous.review(.init(
            scope: .periods(fixture.periods),
            action: .select(RecordingReviewTestSupport.first),
        ))
        await previous.apply()
        #expect(previous.presentation == nil)
        #expect(try await fixture.controls().sourceChoices.isEmpty)
        model.inspection = nil
        await replacement.load()
        #expect(replacement.presentation == nil)
    }

    @Test func invalidBoundsRemainObservableAndDoNotOpenAReview() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingHistoryModel(
            services: fixture.services,
            now: { RecordingReviewTestSupport.date(86400) },
        )
        for start in [
            model.end,
            model.end.addingTimeInterval(1),
            Date(timeIntervalSince1970: .infinity),
        ] {
            model.start = start
            #expect(!model.canInspect)
            model.inspect()
            #expect(model.inspection == nil)
            #expect(model.error != nil)
        }
    }

    @Test func revocationClearsAndRetiresAnExistingInspection() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingHistoryModel(
            services: fixture.services,
            now: { RecordingReviewTestSupport.date(86400) },
        )
        model.inspect()
        let child = try #require(model.inspection?.model)
        await child.load()
        await fixture.services.retireCompatibilityScope()
        model.inspect()
        #expect(model.inspection == nil)
        #expect(child.presentation == nil)
        #expect(model.error as? DataCompatibilityAccess.AccessError == .revoked)
    }

    @Test func retirementAndOwnerReleaseRejectFurtherIntents() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        var owner: RecordingHistoryModel? = .init(
            services: fixture.services,
            now: { RecordingReviewTestSupport.date(86400) },
        )
        owner?.inspect()
        let child = try #require(owner?.inspection?.model)
        owner = nil
        await child.load()
        #expect(child.presentation == nil)
        let model = RecordingHistoryModel(
            services: fixture.services,
            now: { RecordingReviewTestSupport.date(86400) },
        )
        model.deactivate()
        model.inspect()
        #expect(!model.canInspect)
        #expect(model.inspection == nil)
    }

    @Test func foundationScopesDoNotOfferInspection() {
        let model = RecordingHistoryModel(
            services: PreviewSupport.previewServices(),
            now: { PreviewSupport.referenceNow },
        )
        #expect(!model.isAvailable)
        #expect(!model.canInspect)
        model.inspect()
        #expect(model.inspection == nil)
    }
}
