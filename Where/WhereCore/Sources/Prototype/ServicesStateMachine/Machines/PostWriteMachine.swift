import Foundation

/// Sequential post-write fan-out (`PostWriteReconcile.tla`).
enum PostWriteMachine {
    enum WritePhase: String, Hashable, CaseIterable {
        case idle
        case inPerform
        case committed
    }

    enum ReconcilePhase: String, Hashable, CaseIterable {
        case none
        case running
        case done
    }

    struct State: Equatable {
        var writePhase: WritePhase
        var reconcilePhase: ReconcilePhase
        var pendingPlan: PostWriteReconcilePlan?
        var nextStepIndex: Int
        var changesPinged: Bool
        var sideEffectsApplied: Bool
        var readerSawPing: Bool

        static let initial = State(
            writePhase: .idle,
            reconcilePhase: .none,
            pendingPlan: nil,
            nextStepIndex: 0,
            changesPinged: false,
            sideEffectsApplied: false,
            readerSawPing: false,
        )
    }

    static func reduce(
        _ state: State,
        event: ServicesEvent,
    ) -> (State, [ServiceEffect])? {
        switch event {
            case .beginWrite:
                guard state.writePhase == .idle else { return nil }
                var next = state
                next.writePhase = .inPerform
                return (next, [.beginStorePerform])
            case let .writeCommitted(outcome):
                guard state.writePhase == .inPerform else { return nil }
                var next = state
                next.writePhase = .committed
                next.reconcilePhase = .running
                next.pendingPlan = PostWriteReconcilePlan.forOutcome(outcome)
                next.nextStepIndex = 0
                return (next, [.commitStoreWrite] + effectsForNextStep(next))
            case .storePerformCompleted:
                return nil
            case let .reconcileStepFinished(step):
                return advanceReconcile(state, finished: step)
            case .storeChangesPinged:
                guard state.writePhase == .committed else { return nil }
                var next = state
                next.changesPinged = true
                return (next, [])
            case .readerRefreshed:
                guard state.changesPinged else { return nil }
                var next = state
                next.readerSawPing = true
                return (next, [])
            default:
                return nil
        }
    }

    private static func advanceReconcile(
        _ state: State,
        finished step: ReconcileStep,
    ) -> (State, [ServiceEffect])? {
        guard state.reconcilePhase == .running,
              let plan = state.pendingPlan,
              state.nextStepIndex < plan.steps.count,
              plan.steps[state.nextStepIndex] == step
        else { return nil }

        var next = state
        next.nextStepIndex += 1
        if next.nextStepIndex >= plan.steps.count {
            next.reconcilePhase = .done
            next.sideEffectsApplied = true
            next.pendingPlan = nil
            return (next, [.pingStoreChanges])
        }
        return (next, effectsForNextStep(next))
    }

    private static func effectsForNextStep(_ state: State) -> [ServiceEffect] {
        guard let plan = state.pendingPlan,
              state.nextStepIndex < plan.steps.count
        else { return [] }
        return [effect(for: plan.steps[state.nextStepIndex])]
    }

    private static func effect(for step: ReconcileStep) -> ServiceEffect {
        switch step {
            case .invalidateIssues:
                .invalidateIssueScanner
            case .reconcileReminders:
                .reconcileReminders
            case .reconcileIssueAlerts:
                .reconcileIssueAlerts
            case .publishWidgets:
                .publishWidgets
            case let .publishWidgetsAfterIngest(sample):
                .publishWidgetsAfterIngest(sample)
        }
    }
}
