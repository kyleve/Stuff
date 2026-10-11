import LifecycleKit
import Observation
import WhereCore

/// Connects compatibility to launch even when there is no foreground view tree.
@MainActor
final class WhereCompatibilityLifecycle {
    private var interruptionScheduled = false

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
        guard !interruptionScheduled, needsInterruption(phase) else { return }
        interruptionScheduled = true
        Task { @MainActor [weak runner, weak model] in
            self.interruptionScheduled = false
            guard let runner, let model else { return }
            // Observation callbacks can coalesce. The queued interruption must
            // still apply to the current gate or launch step.
            guard !model.isInDemoMode, !model.compatibility.isCompatible,
                  model.compatibility.state != .checking,
                  self.needsInterruption(runner.phase) else { return }
            await runner.teardown(
                LaunchPlan(SuspendCompatibilityStep(model: model).measured()),
                input: (),
            )
            self.reconcile(runner: runner, model: model)
        }
    }

    private func needsInterruption(_ phase: LifecycleRunner<WhereSession>.Phase) -> Bool {
        switch phase {
            case .launching: false
            case .ready: true
            case let .awaitingGate(handle):
                handle.id == AnyHashable(LaunchStepID.onboarding)
            case let .running(context):
                needsCompatibility(context.stepID)
            case let .failed(failure):
                needsCompatibility(failure.stepID)
        }
    }

    private func needsCompatibility(_ stepID: AnyHashable) -> Bool {
        guard let step = stepID.base as? LaunchStepID else { return false }
        return switch step {
            case .onboarding, .resolveScope, .startSession, .syncAuth, .reconcileTracking,
                 .captureToday, .reminders, .summary, .issueAlerts, .widgetSnapshot: true
            case .activateDemo, .compatibility, .suspendCompatibility, .eraseData,
                 .resetPreferences, .exitDemo, .rejoinDevice: false
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
