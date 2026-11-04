import LifecycleKit
import Observation
import WhereCore

/// Retires incompatible sessions even during a headless launch with no view tree.
@MainActor
final class WhereCompatibilityLifecycle {
    private var interruptionScheduled = false
    private var notifiedBlockedHandoff = false

    static func observe(runner: LifecycleRunner<WhereSession>, model: WhereModel) {
        WhereCompatibilityLifecycle().observe(runner: runner, model: model)
    }

    /// Promotion makes the splash visible immediately; verification remains coalesced with launch.
    static func enterForeground(runner: LifecycleRunner<WhereSession>, model: WhereModel) async {
        async let refresh: Void = model.refreshDataCompatibilityIfNeeded()
        await runner.enterForeground()
        await refresh
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
        let compatible = model.isDataCompatible
        let phase = runner.phase
        guard !model.isInDemoMode else { return }
        if compatible {
            notifiedBlockedHandoff = false
            if let handle = phase.gateHandle, handle.id == AnyHashable(LaunchStepID.compatibility) {
                handle.complete()
            }
            return
        }
        // Setup can discover incompatible history before it owns a scope. Complete parked
        // handoffs with the known failure even though there is no session to retire.
        switch model.compatibility.state {
            case .updateRequired, .failed:
                if !notifiedBlockedHandoff {
                    notifiedBlockedHandoff = true
                    Task {
                        guard !model.isDataCompatible else { return }
                        await model.onDataCompatibilityBlocked(model.compatibility.blockingError)
                    }
                }
            case .notChecked, .available: break
        }
        guard model.compatibility.hasChecked,
              !interruptionScheduled,
              needsInterruption(phase, hasScope: model.activeScope != nil) else { return }
        interruptionScheduled = true
        Task { @MainActor [weak runner, weak model] in
            defer {
                self.interruptionScheduled = false
                if let runner, let model { self.reconcile(runner: runner, model: model) }
            }
            guard let runner, let model, !model.isInDemoMode, !model.isDataCompatible,
                  self.needsInterruption(runner.phase, hasScope: model.activeScope != nil)
            else { return }
            if runner.phase.gateHandle?.id == AnyHashable(LaunchStepID.onboarding) {
                // Keep the gate and its draft alive. Setup can request a new admitted scope
                // after retry without losing its selected archive or region customizations.
                await model.suspendForCompatibility()
            } else {
                await runner.teardown(
                    LaunchPlan(SuspendCompatibilityStep(model: model).measured()),
                    input: (),
                )
            }
        }
    }

    private func needsInterruption(
        _ phase: LifecycleRunner<WhereSession>.Phase,
        hasScope: Bool,
    ) -> Bool {
        switch phase {
            case .launching: false
            case .ready: true
            case let .awaitingGate(handle):
                hasScope && (
                    handle.id == AnyHashable(LaunchStepID.onboarding)
                        || handle.id == AnyHashable(LaunchStepID.compatibility)
                )
            case let .running(context): needsCompatibility(context.stepID)
            case let .failed(failure): needsCompatibility(failure.stepID)
        }
    }

    private func needsCompatibility(_ stepID: AnyHashable) -> Bool {
        guard let step = stepID.base as? LaunchStepID else { return false }
        return switch step {
            case .resolveScope, .startSession, .syncAuth, .reconcileTracking,
                 .captureToday, .reminders, .summary, .issueAlerts, .widgetSnapshot: true
            case .activateDemo, .resolveInstallation, .onboarding, .compatibility,
                 .suspendCompatibility, .eraseData, .resetPreferences, .exitDemo,
                 .rejoinDevice: false
        }
    }
}

struct DataCompatibilityGate: LifecycleGate {
    let model: WhereModel
    let id = LaunchStepID.compatibility
    let modes: LifecycleModeSet = .all

    func isNeeded(_ context: ResolveInstallationContextStep.Context) async -> Bool {
        if model.isInDemoMode { return false }
        if case let .installation(installation) = context {
            // A new installation has not chosen a real world yet. Discovery and Finish
            // request admission explicitly. An interrupted import already crossed that choice.
            let resumesImport = model.hasInterruptedOnboardingImport
                && installation.automaticRecordingEnabled != nil
            guard resumesImport || (model.hasOnboarded && installation.hasCompletedSetup)
            else { return false }
        }
        await model.compatibility.refresh()
        if !model.isDataCompatible {
            await model.onDataCompatibilityBlocked(model.compatibility.blockingError)
        }
        return !model.isDataCompatible
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
