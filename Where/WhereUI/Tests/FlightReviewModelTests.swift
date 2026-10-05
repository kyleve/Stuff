import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct FlightReviewModelTests {
    @Test func pointConfirmationAppliesAndRestoresWithoutClosingTheReview() async throws {
        let store = try TestStore()
        let now = FlightReviewTestSupport.date(hour: 18)
        let report = YearReportModel(
            services: FlightReviewTestSupport.services(store: store, now: now),
            selectedYear: 2026,
            preferences: makePreferences(),
            now: { now },
        )
        try await FlightReviewTestSupport.seed(into: store, includeArrival: true)
        await report.refresh()
        await report.rescanForIssues()
        let review = try #require(report.correctionReviews.first)
        let model = FlightReviewModel(review: review, report: report)
        let include = try #require(review.pointCorrections.first)
        model.selectPointCorrection(include)
        #expect(model.isConfirmingPointCorrection)
        // SwiftUI dismisses a confirmation before its asynchronous action resumes.
        model.isConfirmingPointCorrection = false
        await model.applyPointCorrection(include)
        #expect(model.saveState == .pointApplied)
        #expect(model.review != nil)
        #expect(model.canEditPoints)
        let revisions = try await store.allSampleAttributionRevisions()
        #expect(revisions.count == 1)
        #expect(revisions.first?.sampleID == include.sampleID)
        let restore = try #require(model.recordedPoints.first { $0.id == include.sampleID }?
            .correction)
        #expect(restore.action == .restoreGPS)
        model.selectPointCorrection(restore)
        await model.applyPointCorrection(restore)
        #expect(model.saveState == .pointApplied)
        #expect(try await store.allSampleAttributionRevisions().count == 2)
        #expect(model.recordedPoints.first { $0.id == include.sampleID }?.correction?
            .action == .includeInFlight)
    }

    @Test func pointCorrectionKeepsChangedEvidenceOpenForReview() async throws {
        let store = try TestStore()
        let now = FlightReviewTestSupport.date(hour: 18)
        let report = YearReportModel(
            services: FlightReviewTestSupport.services(store: store, now: now),
            selectedYear: 2026,
            preferences: makePreferences(),
            now: { now },
        )
        try await FlightReviewTestSupport.seed(into: store, includeArrival: true)
        await report.refresh()
        await report.rescanForIssues()
        let review = try #require(report.correctionReviews.first)
        let model = FlightReviewModel(review: review, report: report)
        let correction = try #require(review.pointCorrections.first)
        model.selectPointCorrection(correction)
        try await store.perform {
            try await store.add(sample: LocationSample(
                timestamp: FlightReviewTestSupport.date(hour: 17.75),
                coordinate: FlightReviewTestSupport.destination,
                horizontalAccuracy: 20,
                source: .gpsSignificantChange,
                recordingDeviceID: CurrentRecordingDevice.preview.id,
            ))
        }
        await model.applyPointCorrection(correction)
        #expect(model.saveState == .refreshed)
        #expect(model.review != review)
        #expect(model.pointConfirmation == nil)
        #expect(try await store.allSampleAttributionRevisions().isEmpty)
    }

    @Test func anUpdatedScanDismissesTheOldPointConfirmation() throws {
        let review = PreviewSupport.flightReview(state: .ready)
        let model = FlightReviewModel(
            review: review,
            report: PreviewSupport.loadedYearReportModel(),
        )
        try model.selectPointCorrection(#require(review.pointCorrections.first))
        #expect(model.isConfirmingPointCorrection)
        model.receive(PreviewSupport.flightScan(state: .completed))
        #expect(model.pointConfirmation == nil)
        #expect(model.saveState == .refreshed)
    }

    @Test func duplicateSyncedPointsDisplayOneRowPerEdit() async throws {
        let store = try TestStore()
        let now = FlightReviewTestSupport.date(hour: 18)
        let report = YearReportModel(
            services: FlightReviewTestSupport.services(store: store, now: now),
            selectedYear: 2026,
            preferences: makePreferences(),
            now: { now },
        )
        try await FlightReviewTestSupport.seed(into: store, includeArrival: true)
        await report.refresh()
        await report.rescanForIssues()
        let review = try #require(report.correctionReviews.first { $0.proposal != nil })
        let proposal = try #require(review.proposal)
        let duplicated = GPSCorrectionReview(
            id: review.id,
            day: review.day,
            points: Array(review.points.reversed()) + review.points,
            state: review.state,
            flights: review.flights,
        )
        let model = FlightReviewModel(review: duplicated, report: report)

        let displayed = model.editedPoints
        #expect(displayed.count == proposal.edits.count)
        #expect(Set(displayed.map(\.sample.id)) == Set(proposal.edits.map(\.sampleID)))
        #expect(displayed.map(\.sample.timestamp) == displayed.map(\.sample.timestamp).sorted())
        #expect(model.editedPoints == displayed)
        #expect(model.review?.points == duplicated.points)
    }

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

    @Test func mixedReviewOffersOnlyCompletedEditsAndRetainsPendingInformation() throws {
        let review = PreviewSupport.mixedFlightReview()
        let pendingFlight = review.flights.first(where: \.isPending)
        let pending = try #require(pendingFlight)
        let model = FlightReviewModel(
            review: review,
            report: PreviewSupport.loadedYearReportModel(),
        )

        #expect(model.canApply)
        #expect(Set(model.editedPoints.map(\.sample.id))
            .isDisjoint(with: pending.airborneSampleIDs))

        let informational = try #require(review.dismissingProposal())
        model.receive(DataIssueScanResult(
            revision: UUID(),
            issues: [],
            reviews: [informational],
            nextReassessmentAt: nil,
        ))

        #expect(model.canApply == false)
        #expect(model.review?.isPending == true)
        #expect(model.review?.flights == review.flights)
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
