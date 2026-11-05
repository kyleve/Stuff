import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// Opens a read-only source inspection for an explicit physical interval. The child owns
/// any later reviewed choice; changing this draft never changes that child's scope.
@MainActor
@Observable
final class RecordingHistoryModel {
    struct Inspection: Identifiable {
        struct ID: Hashable { let value = UUID() }
        let id = ID()
        let model: RecordingChoiceModel
    }

    var start: Date
    var end: Date
    var inspection: Inspection? {
        didSet {
            guard oldValue?.id != inspection?.id else { return }
            oldValue?.model.deactivate()
        }
    }

    private(set) var error: (any Error)?
    private var retired = false
    private let services: WhereServices
    private static let logger = WhereLog.session(RecordingReviewModelLog.self)

    init(services: WhereServices, now: @Sendable () -> Date) {
        self.services = services
        let current = now()
        end = current
        // A rolling duration is only an initial physical-range draft, never a recording-day
        // assignment.
        start = current.addingTimeInterval(-24 * 60 * 60)
    }

    isolated deinit { inspection?.model.deactivate() }

    var period: Result<RecordingPeriod, any Error> {
        Result { try RecordingPeriod(start: start, end: end) }
    }

    var isAvailable: Bool {
        !retired && services.recordingControlEdits.supportsRecordingControls
    }

    var canInspect: Bool {
        guard isAvailable else { return false }
        switch period {
            case .success: return true
            case .failure: return false
        }
    }

    var isShowingError: Bool {
        get { error != nil }
        set { if !newValue { error = nil } }
    }

    func inspect() {
        guard isAvailable else { return }
        do {
            try services.validateDataAccess()
        } catch {
            inspection = nil
            present(error)
            return
        }
        do {
            let requestedPeriod = try period.get()
            inspection = Inspection(model: RecordingChoiceModel(
                services: services,
                periods: [requestedPeriod],
            ))
            error = nil
        } catch {
            present(error)
        }
    }

    private func present(_ error: any Error) {
        self.error = error
        Self.logger.operationFailed(error: .restricted(.errorDetails, error))
    }

    func deactivate() {
        retired = true
        inspection = nil
    }
}
