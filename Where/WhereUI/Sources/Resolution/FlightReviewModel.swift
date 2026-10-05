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
        case pointApplied
    }

    private var presentation: FlightReviewPresentation?
    var review: GPSCorrectionReview? {
        presentation?.review
    }

    private(set) var saveState = SaveState.idle
    private(set) var pointConfirmation: FlightPointCorrection?
    let reviewID: DataIssueID
    let initialDay: DayPresence
    private let report: YearReportModel
    private static let logger = WhereLog.session(ResolveModelLog.self)

    init(review: GPSCorrectionReview, report: YearReportModel) {
        presentation = Self.prepare(review)
        reviewID = review.id
        initialDay = review.day
        self.report = report
    }

    var canApply: Bool {
        review?.proposal != nil && saveState != .applying && saveState != .applied
    }

    var mapData: RecordedMapData {
        presentation?.map ?? .empty
    }

    var editedPoints: [SampleCorrectionPoint] {
        presentation?.editedPoints ?? []
    }

    var recordedPoints: [FlightReviewPresentation.Point] {
        presentation?.recordedPoints ?? []
    }

    var canEditPoints: Bool {
        saveState != .applying && saveState != .applied
    }

    var isConfirmingPointCorrection: Bool {
        get { pointConfirmation != nil }
        set { if !newValue { pointConfirmation = nil } }
    }

    func selectPointCorrection(_ correction: FlightPointCorrection) {
        guard canEditPoints, review?.pointCorrections.contains(correction) == true else { return }
        pointConfirmation = correction
    }

    func inferredExplanation(for sampleID: UUID) -> String? {
        presentation?.inferredEndpoints[sampleID].map {
            FlightReviewPresentation.Point.Evidence.inferred($0).explanation
        }
    }

    func replacementDescription(for sampleID: UUID) -> String {
        guard let regions = presentation?.replacements[sampleID] else {
            return String(localized: .flightReviewUnchanged)
        }
        if regions.isEmpty { return String(localized: .flightReviewExcluded) }
        return regions.map(\.localizedName).sorted().joined(separator: ", ")
    }

    func receive(_ scan: DataIssueScanResult?) {
        guard let scan, saveState != .applying, saveState != .applied else { return }
        let updated = scan.reviews.first { $0.id == reviewID }
        guard updated != review else { return }
        pointConfirmation = nil
        presentation = updated.map(Self.prepare)
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
                    presentation = updated.map(Self.prepare)
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

    func applyPointCorrection(_ correction: FlightPointCorrection) async {
        guard canEditPoints, correction.day == initialDay.day else { return }
        pointConfirmation = nil
        saveState = .applying
        do {
            switch try await report.services.corrections.apply(correction) {
                case .applied:
                    await report.rescanForIssues()
                    let updated = try await report.services.corrections.review(
                        id: reviewID,
                        year: initialDay.day.year,
                        primaryRegions: report.ranking.primary.map(\.region),
                        driftThresholdMeters: Double(report.driftThreshold.rawValue),
                    )
                    presentation = updated.map(Self.prepare)
                    saveState = .pointApplied
                case let .stale(updated):
                    presentation = updated.map(Self.prepare)
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

    private static func prepare(_ review: GPSCorrectionReview) -> FlightReviewPresentation {
        logger.measure(.prepareReview, budget: .milliseconds(100)) {
            FlightReviewPresentation(review: review)
        }
    }
}
