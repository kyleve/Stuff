import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct FlightReviewModelTests {
    @Test func pendingFlightCannotApply() async throws {
        let store = try TestStore()
        let now = FlightReviewTestSupport.date(hour: 16.5)
        let services = FlightReviewTestSupport.services(store: store, now: now)
        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
            now: { now },
        )
        try await FlightReviewTestSupport.seed(into: store, includeArrival: false)
        await report.refresh()
        await report.rescanForIssues()
        let review = try #require(report.correctionReviews.first)
        let model = FlightReviewModel(review: review, report: report)

        #expect(!model.canApply)
        await model.apply()
        #expect(model.saveState == .idle)
        #expect(try await store.allSampleAttributionRevisions().isEmpty)
    }

    @Test func lateEvidenceRefreshesReviewInsteadOfReportingSuccess() async throws {
        let store = try TestStore()
        let now = FlightReviewTestSupport.date(hour: 18)
        let services = FlightReviewTestSupport.services(store: store, now: now)
        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
            now: { now },
        )
        try await FlightReviewTestSupport.seed(into: store, includeArrival: true)
        await report.refresh()
        await report.rescanForIssues()
        let review = try #require(report.correctionReviews.first { $0.proposal != nil })
        let model = FlightReviewModel(review: review, report: report)
        let late = LocationSample(
            timestamp: FlightReviewTestSupport.date(hour: 17.75),
            coordinate: FlightReviewTestSupport.destination,
            horizontalAccuracy: 20,
            source: .gpsSignificantChange,
            recordingDeviceID: CurrentRecordingDevice.preview.id,
        )
        try await store.perform { try await store.add(sample: late) }

        await model.apply()

        #expect(model.saveState == .refreshed)
        #expect(model.review != review)
        #expect(try await store.allSampleAttributionRevisions().isEmpty)
    }

    @Test func appliesReviewedSamplesAndRefreshesScene() async throws {
        let store = try TestStore()
        let now = FlightReviewTestSupport.date(hour: 18)
        let services = FlightReviewTestSupport.services(store: store, now: now)
        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
            now: { now },
        )
        try await FlightReviewTestSupport.seed(into: store, includeArrival: true)
        await report.refresh()
        await report.rescanForIssues()
        let review = try #require(report.correctionReviews.first { $0.proposal != nil })
        let proposal = try #require(review.proposal)
        let model = FlightReviewModel(review: review, report: report)

        await model.apply()

        #expect(model.saveState == .applied)
        #expect(!model.canApply)
        #expect(try await store.allSampleAttributionRevisions().count == proposal.edits.count)
        #expect(report.correctionReviews.allSatisfy { $0.proposal == nil })
    }

    @Test func failedApplyKeepsTheReviewedProposalVisible() async throws {
        let store = try TestStore()
        let now = FlightReviewTestSupport.date(hour: 18)
        let services = FlightReviewTestSupport.services(store: store, now: now)
        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
            now: { now },
        )
        try await FlightReviewTestSupport.seed(into: store, includeArrival: true)
        await report.refresh()
        await report.rescanForIssues()
        let review = try #require(report.correctionReviews.first { $0.proposal != nil })
        let model = FlightReviewModel(review: review, report: report)
        await store.failSamples()

        await model.apply()

        guard case .failed = model.saveState else {
            Issue.record("Expected an observable correction failure")
            return
        }
        #expect(model.review == review)
        #expect(model.canApply)
        #expect(try await store.allSampleAttributionRevisions().isEmpty)
    }

    @Test func openReviewReceivesArrivalAndRevokedCorrection() {
        let report = PreviewSupport.loadedYearReportModel()
        let pending = PreviewSupport.flightReview(state: .flightLikely)
        let ready = PreviewSupport.flightReview(state: .ready)
        let model = FlightReviewModel(review: pending, report: report)
        #expect(!model.canApply)

        model.receive(DataIssueScanResult(
            revision: UUID(),
            issues: [],
            reviews: [ready],
            nextReassessmentAt: nil,
        ))
        #expect(model.canApply)
        #expect(model.saveState == .refreshed)

        model.receive(DataIssueScanResult(
            revision: UUID(),
            issues: [],
            reviews: [],
            nextReassessmentAt: nil,
        ))
        #expect(!model.canApply)
        #expect(model.review == nil)
        #expect(model.initialDay == pending.day)
    }
}
