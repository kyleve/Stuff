import Foundation

/// Top-level reducer: one snapshot in, updated snapshot + scheduled effects out.
///
/// Each sub-machine owns a slice of ``ServicesSnapshot`` and ignores events
/// outside its domain. The orchestrator merges partial updates and concatenates
/// effects. Cross-machine glue (reset → quiesce → erase, launch → tracking)
/// lives here.
///
/// Prototype-only — production still uses actors + ad-hoc tasks.
enum ServicesMachine {
    struct StepResult: Equatable {
        let snapshot: ServicesSnapshot
        let effects: [ServiceEffect]

        init(snapshot: ServicesSnapshot, effects: [ServiceEffect]) {
            self.snapshot = snapshot
            self.effects = effects
        }
    }

    static func reduce(
        _ snapshot: ServicesSnapshot,
        _ event: ServicesEvent,
    ) -> StepResult {
        var next = snapshot
        var effects: [ServiceEffect] = []

        if let reset = ResetMachine.reduce(next.reset, event: event) {
            next.reset = reset.0
            effects.append(contentsOf: reset.1)
            if case .resetRequested = event {
                if let ingestor = IngestorMachine.reduce(
                    next.ingestor,
                    event: .ingestorQuiesceRequested,
                ) {
                    next.ingestor = ingestor.0
                }
            }
        }

        let sessionActive = next.reset.phase == .idle || next.reset.phase == .done
        if sessionActive {
            if let tracking = TrackingMachine.reduce(next.tracking, event: event) {
                next.tracking = tracking.0
                effects.append(contentsOf: tracking.1)
            }
            if let postWrite = PostWriteMachine.reduce(next.postWrite, event: event) {
                next.postWrite = postWrite.0
                effects.append(contentsOf: postWrite.1)
            }
            if let launch = LaunchMachine.reduce(next.launch, event: event) {
                next.launch = launch.0
                effects.append(contentsOf: launch.1)
            }
        }

        if let ingestor = IngestorMachine.reduce(next.ingestor, event: event) {
            next.ingestor = ingestor.0
            effects.append(contentsOf: ingestor.1)
        }

        effects.append(contentsOf: bridgeTracking(from: next, effects: effects))

        return StepResult(snapshot: next, effects: effects)
    }

    /// Launch emits `.reconcileTracking`; expand it into tracking-lane effects.
    private static func bridgeTracking(
        from snapshot: ServicesSnapshot,
        effects: [ServiceEffect],
    ) -> [ServiceEffect] {
        guard effects.contains(.reconcileTracking) else { return [] }
        return TrackingMachine.reduce(snapshot.tracking, event: .reconcileTrackingRequested)?
            .1 ?? []
    }
}
