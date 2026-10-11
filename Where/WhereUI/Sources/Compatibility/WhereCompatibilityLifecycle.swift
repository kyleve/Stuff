import LifecycleKit
import Observation
import WhereCore

/// Connects compatibility to launch even when there is no foreground view tree.
@MainActor
final class WhereCompatibilityLifecycle {
    private var restarting = false

    static func observe(runner: LifecycleRunner<WhereSession>, model: WhereModel) {
        WhereCompatibilityLifecycle().observe(runner: runner, model: model)
    }

    private func observe(runner: LifecycleRunner<WhereSession>, model: WhereModel) {
        withObservationTracking {
            reconcile(runner: runner, model: model)
        } onChange: { [weak runner, weak model] in
            Task { @MainActor [weak runner, weak model] in
                guard let runner, let model else { return }
                self.observe(runner: runner, model: model)
            }
        }
    }

    private func reconcile(runner: LifecycleRunner<WhereSession>, model: WhereModel) {
        let state = model.compatibility.state
        let phase = runner.phase
        guard !model.isInDemoMode else { return }
        if case .compatible = state {
            if let handle = phase.gateHandle, handle.id == AnyHashable(LaunchStepID.compatibility) {
                handle.complete()
            }
            return
        }
        if case .checking = state { return }
        guard !restarting, model.activeScope != nil else { return }
        restarting = true
        Task { @MainActor [weak runner, weak model] in
            guard let runner, let model else { return }
            await runner.teardown(
                LaunchPlan(SuspendCompatibilityStep(model: model).measured()),
                input: (),
            )
            self.restarting = false
            self.reconcile(runner: runner, model: model)
        }
    }
}

struct DataCompatibilityGate: LifecycleGate {
    let model: WhereModel
    let id = LaunchStepID.compatibility
    let modes: LifecycleModeSet = .all
    func isNeeded(_: Void) async -> Bool {
        if model.isInDemoMode { return false }
        await model.compatibility.refresh()
        return !model.compatibility.isCompatible
    }
}

struct SuspendCompatibilityStep: BudgetedLaunchStep {
    let model: WhereModel
    let id = LaunchStepID.suspendCompatibility
    let budget: Duration = .seconds(2)
    func run(_: Void, _: LifecycleStepContext) async throws {
        await model.suspendForCompatibility()
    }
}
