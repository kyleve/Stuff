import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// Mirrors the scene's historical publication for navigation and dismiss actions.
@MainActor
@Observable
public final class ResolveModel {
    private var state = ResolutionSourceState.idle
    private var dismissedIssueIDs: Set<DataIssueID> = []
    private var loadRequestID = UUID()
    var recordingReview: RecordingReviewFlowModel?
    private(set) var recordingReviewError: (any Error)?

    private enum ReviewError: Error { case unavailableHistory }

    public var dataIssues: [any DataIssue] {
        (state.scan?.issues ?? []).filter { !dismissedIssueIDs.contains($0.id) }
    }

    public var reviews: [GPSCorrectionReview] {
        (state.scan?.reviews ?? []).compactMap {
            dismissedIssueIDs.contains($0.id) ? $0.dismissingProposal() : $0
        }
    }

    public var recordingIssues: [RecordingIssue] {
        state.scan?.recording.issues ?? []
    }

    public var loadError: (any Error)? {
        state.error
    }

    public var hasLoaded: Bool {
        switch state {
            case .idle: false
            case .loaded, .failed: true
        }
    }

    var snapshot: HistoricalDataIssueScanResult? {
        state.scan
    }

    private let services: WhereServices
    private let source: any ResolutionSource
    private static let logger = WhereLog.session(ResolveModelLog.self)

    public convenience init(services: WhereServices, preferences: WherePreferences) {
        self.init(
            services: services,
            source: ScannerResolutionSource(services: services, preferences: preferences),
        )
    }

    init(services: WhereServices, source: any ResolutionSource) {
        self.services = services
        self.source = source
        receive(source.resolutionState)
    }

    public func load() async {
        let requestID = UUID()
        loadRequestID = requestID
        await source.refreshResolution()
        guard requestID == loadRequestID, !Task.isCancelled else { return }
        receive(source.resolutionState)
    }

    private func receive(_ updated: ResolutionSourceState) {
        do {
            try services.validateDataAccess()
            if updated.scan?.revision != state.scan?.revision { dismissedIssueIDs = [] }
            state = updated
        } catch {
            state = .failed(error, previous: nil)
            dismissedIssueIDs = []
            Self.logger.dataIssueScanFailed(error: .restricted(.errorDetails, error))
        }
    }

    var pendingReviews: [GPSCorrectionReview] {
        reviews.filter(\.isPending)
    }

    var completedReviews: [GPSCorrectionReview] {
        reviews.filter { !$0.isPending && $0.proposal == nil }
    }

    func review(for issue: any DataIssue) -> GPSCorrectionReview? {
        reviews.first { $0.id == issue.id }
    }

    func reviewRecording(_ issue: RecordingIssue) {
        startRecordingReview(issues: [issue])
    }

    func reviewRemainingRecordings() {
        startRecordingReview(issues: recordingIssues)
    }

    private func startRecordingReview(issues: [RecordingIssue]) {
        do {
            try services.validateDataAccess()
            guard let snapshot else { throw ReviewError.unavailableHistory }
            let references = try issues.flatMap { try Array(snapshot.references(for: $0)) }
            recordingReview = try RecordingReviewFlowModel(
                services: services,
                references: references,
            )
            recordingReviewError = nil
        } catch {
            recordingReviewError = error
            Self.logger.dataIssueScanFailed(error: .restricted(.errorDetails, error))
        }
    }

    public func dismiss(_ issue: any DataIssue) async {
        guard issue.isDismissible else { return }
        let revision = state.scan?.revision
        do {
            try await services.journal.dismissIssue(id: issue.id)
            try services.validateDataAccess()
            guard !Task.isCancelled, revision == state.scan?.revision else { return }
            // Retain pending flights while the scene refreshes the shared publication.
            dismissedIssueIDs.insert(issue.id)
        } catch {
            Self.logger.dismissFailed(
                issueID: .restricted(.identifier, issue.id.storeURL.absoluteString),
                error: .restricted(.errorDetails, error),
            )
        }
    }
}
