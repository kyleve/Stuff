import Foundation
import Observation
import RegionKit
import WhereCore

/// Observable state for onboarding's optional, metadata-only Photos scan.
/// The draft is provisional until `OnboardingView` commits its approved import.
@MainActor
@Observable
final class OnboardingPhotoImportModel {
    private static let logger = WhereLog.session(OnboardingViewLog.self)

    enum Activity {
        case offer
        case scanning
        case blocked(PhotoLibraryAuthorization)
        case empty(isLimited: Bool)
        case ready(PhotoHistoryDraft, isLimited: Bool)
        case importing(PhotoHistoryDraft, isLimited: Bool)
    }

    var activity: Activity = .offer
    var errorMessage: String?

    var isShowingError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    var draft: PhotoHistoryDraft? {
        switch activity {
            case let .ready(draft, _), let .importing(draft, _): draft
            case .offer, .scanning, .blocked, .empty: nil
        }
    }

    var isLimited: Bool {
        switch activity {
            case let .empty(isLimited), let .ready(_, isLimited), let .importing(_, isLimited):
                isLimited
            case .offer, .scanning, .blocked: false
        }
    }

    func scan(
        library: any PhotoLocationLibrary,
        year: Int,
        regions: [Region],
        calendar: Calendar,
        now: Date,
    ) async {
        guard case .scanning = activity else { return }
        do {
            var authorization = await library.authorizationStatus()
            if authorization == .notDetermined {
                authorization = await library.requestAuthorization()
            }
            guard authorization == .authorized || authorization == .limited else {
                activity = .blocked(authorization)
                return
            }

            let yearInterval = DayAggregator(
                calendar: calendar,
                timeZone: calendar.timeZone,
            ).yearInterval(year: year)
            let draft = try await Self.logger.measure(.photoScan, budget: .seconds(15)) {
                let assets = try await library.assets(in: DateInterval(
                    start: yearInterval.start,
                    end: min(yearInterval.end, now),
                ))
                return try await PhotoHistoryPlanner().makeDraft(
                    assets: assets,
                    year: year,
                    regions: regions,
                    calendar: calendar,
                    now: now,
                )
            }
            guard Task.isCancelled == false else { return }
            let limited = authorization == .limited
            activity = draft.samples.isEmpty ? .empty(isLimited: limited) : .ready(
                draft,
                isLimited: limited,
            )
        } catch is CancellationError {
            activity = .offer
        } catch {
            activity = .offer
            errorMessage = error.localizedDescription
            Self.logger(attachments: [.error(error, name: "photo-scan-error")]) {
                .photoScanFailed(description: error.localizedDescription)
            }
        }
    }

    func beginScan() {
        errorMessage = nil
        activity = .scanning
    }

    func apply(
        _ decision: PhotoHistoryDraft.DayDecision,
        from start: Date,
        through end: Date,
    ) {
        guard case let .ready(current, limited) = activity else { return }
        var updated = current
        updated.setDecision(
            decision,
            from: CalendarDay(from: start, in: current.calendar),
            through: CalendarDay(from: end, in: current.calendar),
        )
        activity = .ready(updated, isLimited: limited)
    }

    func restoreExcludedDays() {
        guard case let .ready(current, limited) = activity else { return }
        var updated = current
        updated.restoreExcludedDays()
        activity = .ready(updated, isLimited: limited)
    }

    func beginImport() -> PhotoHistoryImport? {
        guard case let .ready(draft, limited) = activity else { return nil }
        activity = .importing(draft, isLimited: limited)
        return draft.approvedImport
    }

    func importFailed(_ error: any Error) {
        guard case let .importing(draft, limited) = activity else { return }
        activity = .ready(draft, isLimited: limited)
        errorMessage = error.localizedDescription
    }

    func importCancelled() {
        guard case let .importing(draft, limited) = activity else { return }
        activity = .ready(draft, isLimited: limited)
    }
}
