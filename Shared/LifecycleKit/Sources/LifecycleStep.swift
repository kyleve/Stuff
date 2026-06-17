import SwiftUI

/// One unit of launch work.
///
/// A step declares *whether* it should run (`condition`), *which* launch
/// reasons it applies to (`allowedModes`), the async `run` body, and an
/// optional `presentation` to show while it runs. Build steps with the
/// `LifecycleStep.work(_:_:)` / `LifecycleStep.interactive(...)` factories and
/// refine them with the chained `.when`/`.modes`/`.presenting` modifiers.
///
/// The closures are `@MainActor`: heavy work should be delegated to actors
/// from inside `run`, keeping the step itself on the main actor so it can
/// drive UI directly.
public struct LifecycleStep: Identifiable {
    /// Stable identity used for retry/teardown matching and parity tests. Typed
    /// as `AnyHashable` so steps carry a real `Hashable` token (a typed enum
    /// case is preferred over a raw string); any `Hashable` converts implicitly.
    public let id: AnyHashable

    var allowedModes: LifecycleModeSet
    var condition: @MainActor () async -> Bool
    var run: @MainActor (LifecycleStepUIBridge) async throws -> Void
    var presentation: LifecycleStepPresentation?

    public init(
        id: AnyHashable,
        condition: @escaping @MainActor () async -> Bool = { true },
        run: @escaping @MainActor (LifecycleStepUIBridge) async throws -> Void,
    ) {
        self.id = id
        allowedModes = .all
        self.condition = condition
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
    public func modes(_ modes: LifecycleModeSet) -> Self {
        var copy = self
        copy.allowedModes = modes
        return copy
    }

    /// Show `view` for the whole time this step runs (e.g. onboarding, whose
    /// entire purpose is the UI).
    public func presenting(
        @ViewBuilder _ view: @escaping @MainActor (LifecycleStepUIBridge) -> some View,
    ) -> Self {
        present(trigger: .always, view)
    }

    /// Show `view` only when `predicate` holds as the step starts (e.g. a
    /// migration UI shown only when a migration is predicted). Otherwise the
    /// step runs silently behind the splash.
    public func presenting(
        when predicate: @escaping @MainActor () -> Bool,
        @ViewBuilder _ view: @escaping @MainActor (LifecycleStepUIBridge) -> some View,
    ) -> Self {
        present(trigger: .when(predicate), view)
    }

    /// Show `view` only if the step is still running after `delay` — a
    /// deferred "this is taking a while" UI that never flashes for fast steps.
    public func presenting(
        after delay: Duration,
        @ViewBuilder _ view: @escaping @MainActor (LifecycleStepUIBridge) -> some View,
    ) -> Self {
        present(trigger: .after(delay: delay, minVisible: .zero), view)
    }

    /// Show `view` only if the step is still running after `delay`, and once it
    /// appears keep it on screen for at least `minVisible` even if the step
    /// finishes — so slow-open UI that *does* appear never flickers away
    /// instantly.
    public func presenting(
        after delay: Duration,
        minVisible: Duration,
        @ViewBuilder _ view: @escaping @MainActor (LifecycleStepUIBridge) -> some View,
    ) -> Self {
        present(trigger: .after(delay: delay, minVisible: minVisible), view)
    }

    /// Whether this step is allowed to run under `reason` (mode filtering,
    /// independent of the async `condition`).
    func appliesTo(_ reason: LifecycleReason) -> Bool {
        allowedModes.contains(reason.modeSet)
    }

    private func present(
        trigger: LifecycleStepPresentation.Trigger,
        _ view: @escaping @MainActor (LifecycleStepUIBridge) -> some View,
    ) -> Self {
        var copy = self
        copy.presentation = LifecycleStepPresentation(trigger: trigger) { bridge in
            AnyView(view(bridge))
        }
        return copy
    }
}

// MARK: - Declarative sugar

extension LifecycleStep {
    /// A silent unit of launch work: runs `body`, shows nothing of its own (the
    /// host's splash stays up) unless you add a `.presenting(...)` modifier.
    public static func work(
        _ id: AnyHashable,
        _ body: @escaping @MainActor (LifecycleStepUIBridge) async throws -> Void,
    ) -> LifecycleStep {
        LifecycleStep(id: id, run: body)
    }

    /// A UI-bearing step that presents `presenting` and, by default, suspends
    /// until the view resolves the bridge (`complete()`/`fail(_:)`). Pass a
    /// custom `run` if the step also needs to do async work alongside awaiting
    /// the UI.
    ///
    /// Interactive steps default to `.modes(.foreground)`: a step whose whole
    /// job is to wait for the user would deadlock during a headless background
    /// launch (there is no UI to resolve it), so it is skipped there. Override
    /// with `.modes(.all)` only if `run` can also resolve itself without the
    /// UI.
    public static func interactive(
        _ id: AnyHashable,
        run: @escaping @MainActor (LifecycleStepUIBridge) async throws
            -> Void = { try await $0.waitForResolution() },
        @ViewBuilder presenting view: @escaping @MainActor (LifecycleStepUIBridge) -> some View,
    ) -> LifecycleStep {
        LifecycleStep(id: id, run: run)
            .presenting(view)
            .modes(.foreground)
    }
}

/// A step's optional UI, plus the rule for when to show it while the step runs.
struct LifecycleStepPresentation {
    enum Trigger {
        /// Show as soon as the step starts.
        case always
        /// Show at step start only if the predicate holds.
        case when(@MainActor () -> Bool)
        /// Show only if the step is still running after `delay`, then keep it up
        /// for at least `minVisible` once shown.
        case after(delay: Duration, minVisible: Duration)
    }

    var trigger: Trigger
    var build: @MainActor (LifecycleStepUIBridge) -> AnyView
}
