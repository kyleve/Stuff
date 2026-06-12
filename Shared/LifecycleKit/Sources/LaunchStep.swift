import SwiftUI

/// One unit of launch work.
///
/// A step declares *whether* it should run (`condition`), *which* launch
/// reasons it applies to (`allowedModes`), the async `run` body, and an
/// optional `presentation` to show while it runs. Build steps with the
/// `Work`/`Interactive` helpers and refine them with the chained
/// `.when`/`.modes`/`.presenting` modifiers.
///
/// The closures are `@MainActor`: heavy work should be delegated to actors
/// from inside `run`, keeping the step itself on the main actor so it can
/// drive UI directly.
public struct LaunchStep: Identifiable {
    public let id: String

    var allowedModes: LaunchModeSet
    var condition: @MainActor () async -> Bool
    var run: @MainActor (StepHandle) async throws -> Void
    var presentation: StepPresentation?

    public init(
        id: String,
        run: @escaping @MainActor (StepHandle) async throws -> Void,
    ) {
        self.id = id
        allowedModes = .all
        condition = { true }
        self.run = run
        presentation = nil
    }

    /// Only run this step when `predicate` returns true at the moment the
    /// engine reaches it. Replaces any previously set condition.
    public func when(_ predicate: @escaping @MainActor () async -> Bool) -> Self {
        var copy = self
        copy.condition = predicate
        return copy
    }

    /// Restrict this step to the given launch reasons (e.g. `.foreground` so
    /// onboarding never runs during a headless background relaunch).
    public func modes(_ modes: LaunchModeSet) -> Self {
        var copy = self
        copy.allowedModes = modes
        return copy
    }

    /// Show `view` for the whole time this step runs (e.g. onboarding, whose
    /// entire purpose is the UI).
    public func presenting(
        @ViewBuilder _ view: @escaping @MainActor (StepHandle) -> some View,
    ) -> Self {
        present(trigger: .always, view)
    }

    /// Show `view` only when `predicate` holds as the step starts (e.g. a
    /// migration UI shown only when a migration is predicted). Otherwise the
    /// step runs silently behind the splash.
    public func presenting(
        when predicate: @escaping @MainActor () -> Bool,
        @ViewBuilder _ view: @escaping @MainActor (StepHandle) -> some View,
    ) -> Self {
        present(trigger: .when(predicate), view)
    }

    /// Show `view` only if the step is still running after `delay` — a
    /// deferred "this is taking a while" UI that never flashes for fast steps.
    public func presenting(
        after delay: Duration,
        @ViewBuilder _ view: @escaping @MainActor (StepHandle) -> some View,
    ) -> Self {
        present(trigger: .after(delay), view)
    }

    /// Whether this step is allowed to run under `reason` (mode filtering,
    /// independent of the async `condition`).
    func appliesTo(_ reason: LaunchReason) -> Bool {
        allowedModes.contains(reason.modeSet)
    }

    private func present(
        trigger: StepPresentation.Trigger,
        _ view: @escaping @MainActor (StepHandle) -> some View,
    ) -> Self {
        var copy = self
        copy.presentation = StepPresentation(trigger: trigger) { handle in
            AnyView(view(handle))
        }
        return copy
    }
}

/// A step's optional UI, plus the rule for when to show it while the step runs.
struct StepPresentation {
    enum Trigger {
        /// Show as soon as the step starts.
        case always
        /// Show at step start only if the predicate holds.
        case when(@MainActor () -> Bool)
        /// Show only if the step is still running after the delay.
        case after(Duration)
    }

    var trigger: Trigger
    var build: @MainActor (StepHandle) -> AnyView
}

// MARK: - Declarative sugar

/// A silent unit of launch work: runs `body`, shows nothing of its own (the
/// host's splash stays up) unless you add a `.presenting(...)` modifier.
public func Work(
    _ id: String,
    _ body: @escaping @MainActor (StepHandle) async throws -> Void,
) -> LaunchStep {
    LaunchStep(id: id, run: body)
}

/// A UI-bearing step that presents `presenting` and, by default, suspends
/// until the view resolves the handle (`complete()`/`fail(_:)`). Pass a custom
/// `run` if the step also needs to do async work alongside awaiting the UI.
public func Interactive(
    _ id: String,
    run: @escaping @MainActor (StepHandle) async throws
        -> Void = { try await $0.waitForResolution() },
    @ViewBuilder presenting view: @escaping @MainActor (StepHandle) -> some View,
) -> LaunchStep {
    LaunchStep(id: id, run: run).presenting(view)
}
