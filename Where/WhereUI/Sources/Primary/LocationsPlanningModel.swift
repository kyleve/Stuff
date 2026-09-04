import Observation

/// Transactional state for removing the Locations tab's single planned stay.
@MainActor
@Observable
final class LocationsPlanningModel {
    private enum OperationState: Equatable {
        case idle
        case clearing
        case failed(String)
    }

    private var operationState: OperationState = .idle

    var isClearing: Bool {
        operationState == .clearing
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

    func clear(using action: @MainActor () async throws -> Void) async {
        guard !isClearing else { return }
        operationState = .clearing
        do {
            try await action()
            operationState = .idle
        } catch {
            operationState = .failed(error.localizedDescription)
        }
    }
}
