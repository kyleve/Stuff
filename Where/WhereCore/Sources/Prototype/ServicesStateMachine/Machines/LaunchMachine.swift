import Foundation

/// Foreground / launch drive (`LaunchLifecycle.tla`).
enum LaunchMachine {
    enum Phase: String, Hashable, CaseIterable {
        case notStarted
        case driving
        case ready
    }

    struct State: Equatable {
        var phase: Phase
        var nextStepIndex: Int
        var syncAuthRuns: Int
        var reconcileRuns: Int

        static let initial = State(
            phase: .notStarted,
            nextStepIndex: 0,
            syncAuthRuns: 0,
            reconcileRuns: 0,
        )

        static let launchSteps: [LaunchStep] = [
            .syncAuthorization,
            .reconcileTracking,
            .captureTodayIfNeeded,
            .applyReminderConfiguration,
            .applySummaryConfiguration,
            .applyIssueAlertConfiguration,
            .refreshWidgetSnapshot,
        ]
    }

    static func reduce(
        _ state: State,
        event: ServicesEvent,
    ) -> (State, [ServiceEffect])? {
        switch event {
            case .launchDriveStarted:
                guard state.phase == .notStarted else { return nil }
                var next = state
                next.phase = .driving
                next.nextStepIndex = 0
                return (next, effectsForCurrentStep(next))
            case .appForegrounded:
                guard state.phase == .ready else { return nil }
                var next = state
                next.phase = .driving
                next.nextStepIndex = 0
                return (next, effectsForCurrentStep(next))
            case let .launchStepFinished(step):
                return advance(state, finished: step)
            default:
                return nil
        }
    }

    private static func advance(
        _ state: State,
        finished step: LaunchStep,
    ) -> (State, [ServiceEffect])? {
        guard state.phase == .driving,
              state.nextStepIndex < State.launchSteps.count,
              State.launchSteps[state.nextStepIndex] == step
        else { return nil }

        var next = state
        switch step {
            case .syncAuthorization:
                next.syncAuthRuns += 1
            case .reconcileTracking:
                next.reconcileRuns += 1
            case .captureTodayIfNeeded,
                 .applyReminderConfiguration,
                 .applySummaryConfiguration,
                 .applyIssueAlertConfiguration,
                 .refreshWidgetSnapshot:
                break
        }
        next.nextStepIndex += 1
        if next.nextStepIndex >= State.launchSteps.count {
            next.phase = .ready
            return (next, [])
        }
        return (next, effectsForCurrentStep(next))
    }

    private static func effectsForCurrentStep(_ state: State) -> [ServiceEffect] {
        guard state.nextStepIndex < State.launchSteps.count else { return [] }
        return [effect(for: State.launchSteps[state.nextStepIndex])]
    }

    private static func effect(for step: LaunchStep) -> ServiceEffect {
        switch step {
            case .syncAuthorization:
                .syncAuthorization
            case .reconcileTracking:
                .reconcileTracking
            case .captureTodayIfNeeded:
                .captureTodayIfNeeded
            case .applyReminderConfiguration:
                .applyReminderConfiguration
            case .applySummaryConfiguration:
                .applySummaryConfiguration
            case .applyIssueAlertConfiguration:
                .applyIssueAlertConfiguration
            case .refreshWidgetSnapshot:
                .refreshWidgetSnapshot
        }
    }
}
