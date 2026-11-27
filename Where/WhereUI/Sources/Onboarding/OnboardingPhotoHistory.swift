import Foundation
import Observation
import SnapshotKit
import SwiftUI
import WhereCore

@MainActor @Observable
final class OnboardingPhotoHistory {
    enum ScanState: Equatable { case idle, scanning(Int, Int), empty, unavailable, failed }
    var state: ScanState = .idle
    private(set) var attempt: UUID?
    var review: PhotoStayReviewModel?
    var conflicts: PhotoHistoryConflicts?
    var useReviewedDays: Set<CalendarDay> = []
    var useReviewedPicks = false
    var receipt: PhotoHistoryReceipt?
    var reviewContext: OnboardingReviewContext?
    var saveError: String?

    func begin() {
        review = nil
        state = .scanning(0, 0)
        attempt = UUID()
    }

    func cancel() {
        attempt = nil
        state = .idle
    }

    func scan(
        _ id: UUID,
        using model: WhereModel,
        selection: PrimaryRegionSelectionModel,
    ) async -> Bool {
        guard attempt == id else { return false }
        guard let reader = model.photoLocationReader else {
            state = .unavailable
            return false
        }
        do {
            let context = try model.compatibility.coordinator.onboardingReviewContext()
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let scan = try await PhotoLocationScanner.scan(
                reader: reader,
                calendar: calendar,
                now: model.onboardingPhotoDate,
            ) { scanned, total in
                await self.updateProgress(id: id, scanned: scanned, total: total)
            }
            try Task.checkCancellation()
            guard try model.compatibility.coordinator.onboardingReviewContext() == context
            else { throw PhotoScanError.accessChanged }
            guard attempt == id else { return false }
            guard !scan.points.isEmpty else { state = .empty; return false }
            reviewContext = context
            review = PhotoStayReviewModel(draft: .init(scan: scan), selection: selection)
            return true
        } catch is CancellationError {
            return false
        } catch {
            if attempt ==
                id { state = (error as? PhotoScanError) == .unavailable ? .unavailable : .failed }
            return false
        }
    }

    private func updateProgress(id: UUID, scanned: Int, total: Int) {
        if attempt == id { state = .scanning(scanned, total) }
    }

    func save(
        using model: WhereModel,
        scope: WhereScope,
        selection: PrimaryRegionSelectionModel,
    ) async throws -> Bool {
        guard let review, let reviewContext else { return true }
        let current = try model.compatibility.coordinator.requireAccess()
        if current.reviewContext != reviewContext {
            // A new grant can acknowledge an already committed receipt, but cannot replay the
            // draft.
            guard let receipt, receipt.domain == current.domain,
                  try await scope.services.hasCommittedPhotoHistory(receipt)
            else {
                throw RecordingPersistenceError.dataGenerationChanged
            }
            try await acknowledge(receipt, using: model, scope: scope, admission: current)
            return true
        }
        let token: PhotoHistoryReceipt
        if let receipt { token = receipt } else {
            token = try await scope.services.preparePhotoReceipt(in: current.domain)
            try model.compatibility.coordinator.requireAccess(current)
            try model.rememberPhotoReceipt(token)
            receipt = token
        }
        let resolution = conflicts.map { PhotoHistoryResolution(
            evidence: $0,
            useReviewedDays: useReviewedDays,
            useReviewedPicks: useReviewedPicks,
        ) }
        if let evidence = try await scope.services.commitPhotoHistory(
            review.draft.approved,
            primary: selection.desiredPrimaryRegions,
            receipt: token,
            resolution: resolution,
        ) {
            conflicts = evidence
            useReviewedDays = []
            useReviewedPicks = false
            return false
        }
        try await acknowledge(token, using: model, scope: scope, admission: current)
        return true
    }

    private func acknowledge(
        _ token: PhotoHistoryReceipt,
        using model: WhereModel,
        scope: WhereScope,
        admission: DataCompatibilityAdmission,
    ) async throws {
        try Task.checkCancellation()
        try model.compatibility.coordinator.requireAccess(admission)
        await scope.services.reconcilePhotoHistory()
        try model.compatibility.coordinator.requireAccess(admission)
        guard try await scope.services.hasCommittedPhotoHistory(token)
        else { throw RecordingPersistenceError.dataGenerationChanged }
        try Task.checkCancellation()
        try model.compatibility.coordinator.requireAccess(admission)
        try model.acknowledgePhotoReceipt(token)
    }
}

struct OnboardingPhotoOffer: View {
    let photo: OnboardingPhotoHistory
    let scan: () -> Void
    let skip: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Text(.photoOfferDescription)
                if case let .scanning(scanned, total) = photo.state {
                    if total > 0 {
                        ProgressView(value: Double(scanned), total: Double(total)) {
                            Text(.photoOfferProgress)
                        }
                    } else { ProgressView { Text(.photoOfferProgress) } }
                    Button { photo.cancel() } label: { Text(.commonCancel) }
                } else {
                    switch photo.state {
                        case .empty: Text(.photoOfferEmpty)
                        case .unavailable: Text(.photoOfferUnavailable)
                        case .failed: Text(.photoOfferFailed)
                        case .idle, .scanning: EmptyView()
                    }
                    Button(action: scan) { Text(.photoOfferScan) }
                }
                Button(action: skip) { Text(.photoOfferSkip) }
            }
            .whereFormRoot()
            .navigationTitle(Text(.photoOfferTitle))
        }
    }
}

#if DEBUG
    extension OnboardingPhotoOffer: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            [whereSnapshot(
                name: "Offer",
                configurations: [
                    .init(device: .iPhone),
                    .init(device: .iPhone, snapshotType: .accessibility),
                ],
                measurementReadiness: .immediate,
            ) {
                OnboardingPhotoOffer(photo: OnboardingPhotoHistory(), scan: {}, skip: {})
            }]
        }
    }

    #Preview { OnboardingPhotoOffer.snapshotPreviews }
#endif
