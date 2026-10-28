import LifecycleKit
import PeriscopeCore
import WhereCore

/// A launch or teardown step that declares how long it is expected to take, so
/// ``measured()`` can wrap it in a budgeted Periscope span.
///
/// The budget is an *expectation*, not a deadline: a step that overruns keeps
/// running and still ends normally, but Periscope emits a `SpanOverdue` warning
/// *while* it hangs — which is what turns "launch felt slow" into "this step was
/// the slow one", even when the step never returns.
///
/// Budgets are sized against the splash's caption delay
/// (`WhereStylesheet`'s `captionDelay`, 1.2s): a trunk step past its budget is
/// roughly the point where the user is about to be told the app is taking a
/// moment. The detached fan-out is looser — it runs after `.ready`, so its cost
/// is invisible to the user and worth flagging only when it's pathological.
///
/// The budget lives on the step rather than on `LaunchStepID` because it
/// describes the work, not the identity — and because the ID domain includes
/// `onboarding`, a gate that parks on the user and so has nothing to budget.
/// Making it a conformance requirement means a new step cannot quietly go
/// unbudgeted.
protocol BudgetedLaunchStep: LifecycleStep where ID == LaunchStepID {
    var budget: Duration { get }
}

extension BudgetedLaunchStep {
    /// This step, wrapped so every run is one Periscope span.
    func measured() -> MeasuredStep<Self> {
        MeasuredStep(wrapping: self)
    }
}

/// Wraps a launch step so each run is a Periscope span named after the step —
/// `step(open-store)`, `step(reminders)`, … — carrying the step's budget. The
/// launch's cost then breaks down per step in the span history instead of
/// arriving as one opaque "launch was slow".
///
/// `id` and `modes` forward untouched, so measuring changes nothing about a
/// step's plan position, run-once memoization, or mode gating. `MeasuredStep`
/// deliberately does *not* conform to ``BudgetedLaunchStep``, so a step cannot
/// be measured twice into nested duplicate spans.
struct MeasuredStep<Wrapped: BudgetedLaunchStep>: LifecycleStep {
    let wrapped: Wrapped
    private let logger: Log<WhereLaunchLog>

    var id: LaunchStepID {
        wrapped.id
    }

    var modes: LifecycleModeSet {
        wrapped.modes
    }

    init(wrapping wrapped: Wrapped) {
        self.init(wrapping: wrapped, spanningInto: LaunchStepSpans.logger)
    }

    /// Span into `logger` rather than the app's launch logger — the seam tests
    /// use to assert the emitted pair against their own Periscope system
    /// instead of the process-wide one.
    init(wrapping wrapped: Wrapped, spanningInto logger: Log<WhereLaunchLog>) {
        self.wrapped = wrapped
        self.logger = logger
    }

    func run(
        _ input: Wrapped.Input,
        _ context: LifecycleStepContext,
    ) async throws -> Wrapped.Output {
        try await logger.measure(.step(id), budget: wrapped.budget) {
            try await wrapped.run(input, context)
        }
    }
}

/// Holds the logger `MeasuredStep` spans through. A generic type can't have a
/// static stored property, so it can't follow the usual
/// `private static let logger` convention — this is the file-scoped stand-in.
private enum LaunchStepSpans {
    static let logger = WhereLog.root(WhereLaunchLog.self)
}
