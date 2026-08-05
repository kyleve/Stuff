import Foundation

/// Cross-collaborator erase path (`WhereServices.reset()` ordering).
enum ResetMachine {
    enum Phase: String, Hashable, CaseIterable {
        case idle
        case quiescing
        case erasing
        case done
    }

    struct State: Equatable {
        var phase: Phase

        static let initial = State(phase: .idle)
    }

    static func reduce(
        _ state: State,
        event: ServicesEvent,
    ) -> (State, [ServiceEffect])? {
        switch event {
            case .resetRequested:
                guard state.phase == .idle else { return nil }
                var next = state
                next.phase = .quiescing
                return (next, [.beginIngestorQuiesce])
            case .ingestorQuiesceFinished:
                guard state.phase == .quiescing else { return nil }
                var next = state
                next.phase = .erasing
                return (next, [.eraseAllData])
            case .eraseAllDataFinished:
                guard state.phase == .erasing else { return nil }
                var next = state
                next.phase = .done
                return (next, [.invalidateIssueScannerAfterReset])
            default:
                return nil
        }
    }
}
