import Observation

/// Transactional presentation state for the Appearance forecast toggle.
/// Disabling stays visually on until the synced planned stay is cleared.
@MainActor
@Observable
final class EstimatedTimeAndPlanningSettingsModel {
    private enum OperationState: Equatable {
        case idle
        case updating
        case failed(String)
    }

    private let report: YearReportModel
    private var enabledStorage: Bool
    private var operationState: OperationState = .idle

    init(report: YearReportModel) {
        self.report = report
        enabledStorage = report.showsEstimatedTimeAndPlanning
    }

    var isEnabled: Bool {
        get { enabledStorage }
        set { request(newValue) }
    }

    var isUpdating: Bool {
        operationState == .updating
    }

    var presentedFailure: String? {
        guard case let .failed(message) = operationState else { return nil }
        return message
    }

    var isShowingError: Bool {
        get { presentedFailure != nil }
        set {
            if !newValue, presentedFailure != nil {
                operationState = .idle
            }
        }
    }

    private func request(_ isEnabled: Bool) {
        guard isEnabled != enabledStorage, !isUpdating else { return }
        Task { await setEnabled(isEnabled) }
    }

    func setEnabled(_ isEnabled: Bool) async {
        guard isEnabled != enabledStorage, !isUpdating else { return }
        operationState = .updating
        do {
            try await report.setEstimatedTimeAndPlanningEnabled(isEnabled)
            enabledStorage = report.showsEstimatedTimeAndPlanning
            operationState = .idle
        } catch {
            enabledStorage = report.showsEstimatedTimeAndPlanning
            operationState = .failed(error.localizedDescription)
        }
    }
}
