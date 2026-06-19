import SwiftUI

/// One unit of launch work.
///
/// A step declares *whether* it should run (`condition`), *which* launch
/// reasons it applies to (`allowedModes`), the async `perform` body, and an
/// optional `presentation` to show while it runs. `condition` and `allowedModes`
/// are fixed at construction (init / `work` / `interactive` parameters) rather
/// than chained modifiers, so a step's run gating is visible where it's built;
/// UI is attached afterwards with the `.presenting` modifiers.
///
/// The closures are `@MainActor`: heavy work should be delegated to actors
/// from inside `perform`, keeping the step itself on the main actor so it can
/// drive UI directly.
public struct LifecycleStep: Identifiable {
    /// Stable identity used for retry/teardown matching and parity tests. Typed
    /// as `AnyHashable` so steps carry a real `Hashable` token (a typed enum
    /// case is preferred over a raw string); any `Hashable` converts implicitly.
    public let id: AnyHashable

    var allowedModes: LifecycleModeSet
    var condition: @MainActor () async -> Bool
    var perform: @MainActor (LifecycleStepUIBridge) async throws -> Void
    var presentation: LifecycleStepPresentation?

    /// - Parameters:
    ///   - id: stable identity for retry/teardown matching.
    ///   - modes: which launch reasons this step runs under (e.g. `.foreground`
    ///     so onboarding never runs during a headless background relaunch).
    ///   - condition: run this step only when the predicate holds at the moment
    ///     the engine reaches it.
    ///   - perform: the async work; delegate heavy lifting to actors from here.
    public init(
        id: AnyHashable,
        modes: LifecycleModeSet = .all,
        condition: @escaping @MainActor () async -> Bool = { true },
        perform: @escaping @MainActor (LifecycleStepUIBridge) async throws -> Void,
    ) {
        self.id = id
        allowedModes = modes
        self.condition = condition
        self.perform = perform
        presentation = nil
    }

    /// Show `view` for the whole time this step runs (e.g. onboarding, whose
    /// entire purpose is the UI).
    ///
    /// `minVisible` keeps the view on screen for at least that long once it
    /// appears, even if the step finishes first — so a fast step never flashes
    /// its UI away instantly. It applies uniformly to every `presenting` trigger.
    public func presenting(
        minVisible: Duration = .zero,
        @ViewBuilder _ view: @escaping @MainActor (LifecycleStepUIBridge) -> some View,
    ) -> Self {
        present(trigger: .always, minVisible: minVisible, view)
    }

    /// Show `view` only when `predicate` holds as the step starts (e.g. a
    /// migration UI shown only when a migration is predicted). Otherwise the
    /// step runs silently behind the splash. See `presenting(minVisible:_:)` for
    /// `minVisible`.
    public func presenting(
        when predicate: @escaping @MainActor () -> Bool,
        minVisible: Duration = .zero,
        @ViewBuilder _ view: @escaping @MainActor (LifecycleStepUIBridge) -> some View,
    ) -> Self {
        present(trigger: .when(predicate), minVisible: minVisible, view)
    }

    /// Show `view` only if the step is still running after `delay` — a deferred
    /// "this is taking a while" UI that never flashes for fast steps. See
    /// `presenting(minVisible:_:)` for `minVisible`.
    public func presenting(
        after delay: Duration,
        minVisible: Duration = .zero,
        @ViewBuilder _ view: @escaping @MainActor (LifecycleStepUIBridge) -> some View,
    ) -> Self {
        present(trigger: .after(delay), minVisible: minVisible, view)
    }

    /// Whether this step is allowed to run under `reason` (mode filtering,
    /// independent of the async `condition`).
    func appliesTo(_ reason: LifecycleReason) -> Bool {
        allowedModes.contains(reason.modeSet)
    }

    private func present(
        trigger: LifecycleStepPresentation.Trigger,
        minVisible: Duration,
        _ view: @escaping @MainActor (LifecycleStepUIBridge) -> some View,
    ) -> Self {
        var copy = self
        copy.presentation = LifecycleStepPresentation(trigger: trigger, minVisible: minVisible) {
            AnyView(view($0))
        }
        return copy
    }
}

// MARK: - Declarative sugar

extension LifecycleStep {
    /// A silent unit of launch work: runs `perform`, shows nothing of its own
    /// (the host's splash stays up) unless you add a `.presenting(...)` modifier.
    public static func work(
        _ id: AnyHashable,
        modes: LifecycleModeSet = .all,
        condition: @escaping @MainActor () async -> Bool = { true },
        _ perform: @escaping @MainActor (LifecycleStepUIBridge) async throws -> Void,
    ) -> LifecycleStep {
        LifecycleStep(id: id, modes: modes, condition: condition, perform: perform)
    }

    /// A UI-bearing step that presents `presenting` and, by default, suspends
    /// until the view resolves the bridge (`complete()`/`fail(_:)`). Pass a
    /// custom `perform` if the step also needs to do async work alongside
    /// awaiting the UI.
    ///
    /// Interactive steps default to `modes: .foreground`: a step whose whole
    /// job is to wait for the user would deadlock during a headless background
    /// launch (there is no UI to resolve it), so it is skipped there. Pass
    /// `modes: .all` only if `perform` can also resolve itself without the UI.
    public static func interactive(
        _ id: AnyHashable,
        modes: LifecycleModeSet = .foreground,
        condition: @escaping @MainActor () async -> Bool = { true },
        perform: @escaping @MainActor (LifecycleStepUIBridge) async throws
            -> Void = { try await $0.waitForResolution() },
        @ViewBuilder presenting view: @escaping @MainActor (LifecycleStepUIBridge) -> some View,
    ) -> LifecycleStep {
        LifecycleStep(id: id, modes: modes, condition: condition, perform: perform)
            .presenting(view)
    }
}

/// A step's optional UI: when to show it (`trigger`), how long to keep it once
/// shown (`minVisible`), and how to build it. `minVisible` is unified here
/// rather than per-trigger so the "don't flash away" guarantee is identical
/// whether the view shows immediately, conditionally, or after a delay.
struct LifecycleStepPresentation {
    enum Trigger {
        /// Show as soon as the step starts.
        case always
        /// Show at step start only if the predicate holds.
        case when(@MainActor () -> Bool)
        /// Show only if the step is still running after `delay`.
        case after(Duration)
    }

    var trigger: Trigger
    /// Once shown, keep the view up for at least this long even if the step
    /// finishes first (`.zero` = no hold).
    var minVisible: Duration
    /// Builds the step's view, type-erased to `AnyView`. Erasure is required so a
    /// heterogeneous `[LifecycleStep]` can share one element type without leaking
    /// each step's concrete view type into `LifecycleStep`/`LifecycleSteps`; the
    /// public `presenting` API still takes `some View`. See
    /// `LifecycleStepUIBridge.presentation` for the full rationale.
    var build: @MainActor (LifecycleStepUIBridge) -> AnyView
}
