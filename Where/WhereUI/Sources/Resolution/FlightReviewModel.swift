import Foundation
import Observation
import PeriscopeCore
import RegionKit
import WhereCore

/// Owns review refresh and transactional Apply; a stale proposal stays on screen
/// with the newly assessed evidence and requires an explicit second review.
@MainActor
@Observable
final class FlightReviewModel {
    enum SaveState: Equatable {
        case idle
        case applying
        case refreshed
        case failed(String)
        case applied
    }

    private(set) var review: GPSCorrectionReview?
    private(set) var saveState = SaveState.idle
    let reviewID: DataIssueID
    let initialDay: DayPresence
    private let report: YearReportModel
    private static let logger = WhereLog.session(ResolveModelLog.self)

    init(review: GPSCorrectionReview, report: YearReportModel) {
        self.review = review
        reviewID = review.id
        initialDay = review.day
        self.report = report
    }

    var canApply: Bool {
        review?.proposal != nil && saveState != .applying && saveState != .applied
    }

    var mapPoints: [RecordedMapPoint] {
        review?.points.flatMap { point in
            point.regions.sorted { $0.rawValue < $1.rawValue }.map { region in
                RecordedMapPoint(
                    coordinate: point.sample.coordinate,
                    horizontalAccuracy: point.sample.horizontalAccuracy,
                    region: region,
                )
            }
        } ?? []
    }

    var editedPoints: [SampleCorrectionPoint] {
        guard let review, let proposal = review.proposal else { return [] }
        let editedIDs = Set(proposal.edits.map(\.sampleID))
        return review.points.filter { editedIDs.contains($0.sample.id) }
            .sorted { $0.sample.timestamp < $1.sample.timestamp }
    }

    func replacementDescription(for sampleID: UUID) -> String {
        guard let edit = review?.proposal?.edits.first(where: { $0.sampleID == sampleID }) else {
            return String(localized: .flightReviewUnchanged)
        }
        if edit.replacementRegions.isEmpty {
            return String(localized: .flightReviewExcluded)
        }
        return edit.replacementRegions.map(\.localizedName).sorted().joined(separator: ", ")
    }

    func receive(_ scan: DataIssueScanResult?) {
        guard let scan, saveState != .applying, saveState != .applied else { return }
        let updated = scan.reviews.first { $0.id == reviewID }
        guard updated != review else { return }
        review = updated
        saveState = .refreshed
    }

    func apply() async {
        guard canApply, let proposal = review?.proposal else { return }
        saveState = .applying
        do {
            switch try await report.services.corrections.apply(proposal) {
                case .applied:
                    saveState = .applied
                    await report.rescanForIssues()
                case let .stale(updated):
                    review = updated
                    saveState = .refreshed
                    await report.rescanForIssues()
            }
        } catch {
            Self.logger(attachments: [.error(error, name: "sample-correction-error")]) {
                .correctionApplyFailed(issueID: reviewID)
            }
            saveState = .failed(error.localizedDescription)
        }
    }
}
