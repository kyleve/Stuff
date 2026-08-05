import Foundation

/// GPS ingestor accept/monitor/quiesce slice (`IngestorQuiesce.tla`).
enum IngestorMachine {
    enum QuiescePhase: String, Hashable, CaseIterable {
        case idle
        case begin
        case awaiting
        case done
    }

    struct State: Equatable {
        var acceptsSamples: Bool
        var isMonitoring: Bool
        var inFlightPersist: Bool
        var quiescePhase: QuiescePhase

        static let initial = State(
            acceptsSamples: true,
            isMonitoring: false,
            inFlightPersist: false,
            quiescePhase: .idle,
        )
    }

    static func reduce(
        _ state: State,
        event: ServicesEvent,
    ) -> (State, [ServiceEffect])? {
        switch event {
            case .ingestorStartFinished:
                var next = state
                next.isMonitoring = true
                return (next, [])
            case .ingestorStopFinished:
                var next = state
                next.isMonitoring = false
                return (next, [])
            case .ingestorQuiesceRequested:
                guard state.quiescePhase == .idle else { return nil }
                var next = state
                next.acceptsSamples = false
                next.isMonitoring = false
                next.quiescePhase = .begin
                return (next, [])
            case .ingestorQuiesceFinished:
                guard state.quiescePhase == .begin || state.quiescePhase == .awaiting else {
                    return nil
                }
                var next = state
                next.isMonitoring = false
                next.quiescePhase = .done
                return (next, [])
            default:
                return nil
        }
    }
}
