import Foundation

/// Coalesced tracking worker (`TrackingReconciliation.tla`, `Coalesced.cfg`).
enum TrackingMachine {
    enum WorkerPhase: String, Hashable, CaseIterable {
        case idle
        case ready
        case starting
        case stopping
    }

    struct State: Equatable {
        var desired: Bool
        var persisted: Bool
        var ingestorActive: Bool
        var published: Bool
        var worker: WorkerPhase
        var targetEffective: Bool
        var authorizationAllowsBackground: Bool
        var reconcilePending: Bool

        static let initial = State(
            desired: false,
            persisted: false,
            ingestorActive: false,
            published: false,
            worker: .idle,
            targetEffective: false,
            authorizationAllowsBackground: true,
            reconcilePending: false,
        )

        func effectiveTracking() -> Bool {
            TrackingReconcile.effectiveTracking(
                desired: desired,
                authorizationAllowsBackground: authorizationAllowsBackground,
            )
        }
    }

    static func reduce(
        _ state: State,
        event: ServicesEvent,
    ) -> (State, [ServiceEffect])? {
        switch event {
            case let .setTrackingDesired(value):
                handleDesiredChange(state, value: value)
            case let .authorizationChanged(allowsBackground):
                handleAuthorizationChange(state, allowsBackground: allowsBackground)
            case .reconcileTrackingRequested, .launchStepFinished(.reconcileTracking):
                enqueueReconcile(state)
            case .ingestorStartFinished:
                handleStartFinished(state)
            case .ingestorStopFinished:
                handleStopFinished(state)
            default:
                nil
        }
    }

    private static func handleDesiredChange(
        _ state: State,
        value: Bool,
    ) -> (State, [ServiceEffect]) {
        var next = state
        next.desired = value
        next.persisted = value
        var effects: [ServiceEffect] = [.persistTrackingDesired(value)]
        let (updated, enqueueEffects) = enqueueWorker(next)
        next = updated
        effects.append(contentsOf: enqueueEffects)
        return (next, effects)
    }

    private static func handleAuthorizationChange(
        _ state: State,
        allowsBackground: Bool,
    ) -> (State, [ServiceEffect]) {
        var next = state
        next.authorizationAllowsBackground = allowsBackground
        return enqueueWorker(next)
    }

    private static func enqueueReconcile(_ state: State) -> (State, [ServiceEffect]) {
        var next = state
        if next.worker == .starting || next.worker == .stopping {
            next.reconcilePending = true
            let effective = next.effectiveTracking()
            if TrackingReconcile.shouldPreemptInFlightStop(targetEffective: effective) {
                next.ingestorActive = false
                return (next, [.stopIngestor])
            }
            return (next, [])
        }
        return enqueueWorker(next)
    }

    private static func enqueueWorker(_ state: State) -> (State, [ServiceEffect]) {
        var next = state
        let effective = next.effectiveTracking()
        switch next.worker {
            case .idle:
                next.worker = .ready
                next.targetEffective = effective
                return (next, effectForTarget(effective))
            case .ready, .starting, .stopping:
                next.reconcilePending = true
                if next.worker == .starting,
                   TrackingReconcile.shouldPreemptInFlightStop(targetEffective: effective)
                {
                    next.worker = .stopping
                    next.targetEffective = effective
                    next.ingestorActive = false
                    return (next, [.stopIngestor])
                }
                return (next, [])
        }
    }

    private static func effectForTarget(_ effective: Bool) -> [ServiceEffect] {
        effective ? [.startIngestor] : [.stopIngestor]
    }

    private static func handleStartFinished(_ state: State) -> (State, [ServiceEffect]) {
        guard state.worker == .ready || state.worker == .starting else {
            return (state, [])
        }
        var next = state
        next.worker = .starting
        next.ingestorActive = true
        return finishWorkerCycle(next)
    }

    private static func handleStopFinished(_ state: State) -> (State, [ServiceEffect]) {
        guard state.worker == .ready || state.worker == .starting || state.worker == .stopping
        else {
            return (state, [])
        }
        var next = state
        next.worker = .stopping
        next.ingestorActive = false
        return finishWorkerCycle(next)
    }

    private static func finishWorkerCycle(_ state: State) -> (State, [ServiceEffect]) {
        var next = state
        let currentEffective = next.effectiveTracking()
        guard currentEffective == next.targetEffective, !next.reconcilePending else {
            next.reconcilePending = false
            let (updated, effects) = enqueueWorker(next)
            return (updated, effects)
        }
        next.worker = .idle
        next.published = currentEffective
        return (next, [.publishTracking(currentEffective)])
    }
}

/// Pure helpers shared with production (`cursor/prototype-tracking-reconcile-pure-core`).
enum TrackingReconcile {
    static func effectiveTracking(
        desired: Bool,
        authorizationAllowsBackground: Bool,
    ) -> Bool {
        desired && authorizationAllowsBackground
    }

    static func shouldPreemptInFlightStop(targetEffective: Bool) -> Bool {
        !targetEffective
    }
}
