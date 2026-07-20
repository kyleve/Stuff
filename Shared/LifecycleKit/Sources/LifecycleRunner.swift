import Observation

/// Drives a `LaunchPlan` to completion, publishing a single observable
/// `phase` the host renders. The engine and every step run on the main actor;
/// heavy work is expected to be delegated to actors from inside a step's body.
///
/// Lifecycle:
/// - The synchronous `initializePrerequisites` runs at `init`, before any
///   async work — use it for the cheap, must-exist-now wiring a background
///   relaunch can't wait for (e.g. installing a `CLLocationManager` delegate).
/// - `run()` walks the plan's trunk in order, threading each node's typed
///   output into the next node's input and skipping nodes whose `modes`
///   don't include the launch reason (only pass-through nodes may gate — see
///   `LaunchPlan`). Detached groups fan out concurrently and never block the
///   trunk. A thrown trunk step parks the runner in `.failed`; `retry()`
///   resumes from the node that failed, feeding it the same memoized input.
/// - `enterForeground()` promotes a runner that started headless (its
///   `reason` was `.background` or `.undetermined`) once a window actually
///   appears, re-driving the plan so the now-applicable foreground-only
///   nodes (gates, foreground work) run.
///
/// Drives never overlap. The internal `State` folds the launch reason, the
/// "has run" flag, and the in-flight drive task into one value so invalid
/// combinations are unrepresentable; `reason` and `phase` are its public
/// projections. A new drive (`run`/`retry`/`enterForeground`/`teardown`)
/// cancels the in-flight one and awaits it draining before starting —
/// cooperative cancellation (a parked gate's `waitForResolution()` throws
/// `CancellationError`) keeps that drain from hanging behind a gate waiting
/// on a tap that will never come.
@MainActor
@Observable
public final class LifecycleRunner<Launch: Sendable> {
    /// The single value the host renders. Each case carries exactly what its
    /// surface needs — and `.ready` carries the trunk's final value, so the
    /// app surface cannot be rendered without the proof the launch produced.
    public enum Phase {
        /// Before (or between) trunk nodes — show the splash.
        case launching
        /// A trunk step is running; its context feeds splash caption/progress.
        case running(LifecycleStepContext)
        /// A gate parked the trunk; the UI resolves the handle to continue.
        case awaitingGate(LifecycleGateHandle)
        /// A trunk node threw. The host shows an error UI offering retry.
        case failed(LifecycleFailure)
        /// The trunk finished — hand its output to the app's main UI.
        /// Detached children may still be draining; they can't regress this.
        case ready(Launch)
    }

    /// The single value the host renders.
    public private(set) var phase: Phase = .launching

    /// Failures from detached (fire-and-forget) children. Deliberately *off*
    /// the phase: a detached failure is observable here (and worth logging by
    /// the consumer) but never fails the drive or blocks `.ready`. Reset when
    /// a fresh attempt begins, like the memoized outputs.
    public private(set) var detachedFailures: [LifecycleFailure] = []

    /// The runner's drive lifecycle. One value so e.g. "not started yet" can't
    /// also hold a drive task, and the launch reason always travels with it.
    private enum State {
        /// Built; `run()` not yet called. Carries the reason it will launch with.
        case notStarted(LifecycleReason)
        /// `run()` (or a re-drive) has started. Carries the current reason and
        /// the most recent drive task — which may already have completed, so
        /// late `run()`/`teardown()`/`enterForeground()` callers can await it.
        case running(reason: LifecycleReason, task: Task<Void, Never>)

        /// The launch reason, which every case carries. Lives on the state so
        /// callers read `state.reason` instead of re-switching at each use site.
        var reason: LifecycleReason {
            switch self {
                case let .notStarted(reason): reason
                case let .running(reason, _): reason
            }
        }
    }

    private var state: State

    /// Why the app launched this time. A not-yet-foreground launch
    /// (`.background` or `.undetermined`) can be promoted to a foreground one
    /// via `enterForeground()`; the container observes this to stop rendering
    /// nothing and start building real UI.
    public var reason: LifecycleReason {
        state.reason
    }

    @ObservationIgnored private let launchNodes: [LaunchPlanNode]

    /// The most recent teardown plan (erased) and its root input, retained so
    /// a `retry()` after a thrown teardown node resumes the teardown (and the
    /// relaunch that follows) rather than re-driving the launch plan over
    /// un-torn-down state. Nil until the first `teardown(_:input:)`.
    private struct RetainedTeardown {
        var nodes: [LaunchPlanNode]
        var input: any Sendable
    }

    @ObservationIgnored private var teardown: RetainedTeardown?

    /// The output of every node that ran to completion during the current
    /// launch attempt, keyed by node ID — both the run-once set (a re-drive
    /// doesn't repeat completed work) and the value store that lets a retry
    /// resume mid-trunk with the input its node originally got.
    ///
    /// Only nodes that actually *ran to completion* are recorded; a node
    /// skipped by mode gating or a gate whose `isNeeded` was false is not, so
    /// it re-evaluates once the launch is promoted. Reset when a *fresh*
    /// attempt begins (first `run()`, and the relaunch after a teardown) so a
    /// reset genuinely re-runs everything; preserved across
    /// `enterForeground()` and `retry()`, which continue the same attempt.
    @ObservationIgnored private var memo: [AnyHashable: any Sendable] = [:]

    /// Where a trunk failure parked, so `retry()` can resume the same walk
    /// with the same input. One value: a resume point always carries the
    /// site it belongs to and the input its node needs.
    private struct FailedResume {
        enum Site {
            case launch
            case teardown
        }

        var site: Site
        var index: Int
        var input: any Sendable
    }

    @ObservationIgnored private var failedResume: FailedResume?

    public init(
        reason: LifecycleReason,
        initializePrerequisites: @MainActor () -> Void = {},
        plan: LaunchPlan<Void, Launch>,
    ) {
        state = .notStarted(reason)
        launchNodes = plan.nodes
        initializePrerequisites()
    }

    /// The in-flight (or most recently finished) drive task, if `run()` has
    /// been called.
    private var currentTask: Task<Void, Never>? {
        if case let .running(_, task) = state { task } else { nil }
    }

    /// Walk the plan once. Safe to call repeatedly; only the first call
    /// drives the nodes, and later callers await that drive instead of
    /// starting a second one. Returns once the trunk *and* its detached
    /// children have drained (`.ready` is published as soon as the trunk
    /// finishes, before the children do).
    public func run() async {
        switch state {
            case let .notStarted(reason):
                // A fresh attempt starts with a clean slate; nothing has run yet.
                memo.removeAll()
                detachedFailures.removeAll()
                await drive(reason: reason, from: 0, input: ())
            case let .running(_, task):
                await task.value
        }
    }

    /// Promote a not-yet-foreground launch (`.background` or `.undetermined`)
    /// to a foreground one and re-drive the plan so foreground-only nodes
    /// (gates, foreground work) now run. No-op for a runner that already
    /// launched in the foreground.
    ///
    /// Call this only once the scene is genuinely active: it fires when a
    /// window exists, which is exactly when a background/undetermined launch
    /// has become a user-visible one. The re-drive skips nodes that already
    /// completed (see `memo`), so work serviced during the headless drive
    /// isn't run a second time.
    public func enterForeground() async {
        guard reason != .userForeground else { return }
        await drive(reason: .userForeground, from: 0, input: ())
    }

    /// Resume from the node that failed, feeding it the same input it
    /// originally got. No-op unless the runner is currently in `.failed`.
    ///
    /// If the failure was in a teardown node (from `teardown(_:input:)`), the
    /// teardown is resumed from that node and the relaunch still follows — so
    /// a failed erase re-erases rather than dropping the user back into the
    /// app over un-torn-down state. Otherwise the launch plan is resumed from
    /// the failed node.
    public func retry() {
        guard case .failed = phase, let resume = failedResume else { return }
        switch resume.site {
            case .launch:
                let reason = reason
                Task { await drive(reason: reason, from: resume.index, input: resume.input) }
            case .teardown:
                Task { await driveTeardown(from: resume.index, input: resume.input) }
        }
    }

    /// Run a teardown `plan` rooted at `input` (logout / erase), then
    /// relaunch from the top so the app returns to its initial state — e.g.
    /// first-run onboarding shows again once the teardown clears the "has
    /// onboarded" flag.
    ///
    /// The plan and input are retained so a `retry()` after a thrown teardown
    /// node resumes the teardown (then the relaunch). If a teardown node
    /// throws, the runner parks in `.failed` and does not relaunch. The
    /// teardown's detached children (if any) are drained *before* the
    /// relaunch begins, so no torn-down-world work overlaps the fresh launch.
    public func teardown<Input: Sendable>(
        _ plan: LaunchPlan<Input, some Sendable>,
        input: Input,
    ) async {
        await teardownErased(nodes: plan.nodes, input: input)
    }

    /// `teardown(_:input:)` after erasure — the `LifecycleDriving` seam the
    /// UI proxy forwards through (see `LifecycleDriving`).
    package func teardownErased(nodes: [LaunchPlanNode], input: any Sendable) async {
        teardown = RetainedTeardown(nodes: nodes, input: input)
        await driveTeardown(from: 0, input: input)
    }

    /// Cancel any in-flight drive, drain it, then run the retained teardown
    /// from `startIndex` followed by a fresh launch from the top — landing in
    /// `.ready` only if both complete. Shared by `teardown(_:input:)` and a
    /// `retry()` resuming a failed teardown node, so the two stay in lockstep.
    private func driveTeardown(from startIndex: Int, input: any Sendable) async {
        guard let teardown else { return }
        let previous = currentTask
        previous?.cancel()
        let reason = reason
        phase = .launching
        failedResume = nil
        let task = Task { [weak self] in
            guard let self else { return }
            await previous?.value
            let tornDown = await withDiscardingTaskGroup(returning: Bool.self) { group in
                let outcome = await self.walk(
                    teardown.nodes,
                    from: startIndex,
                    input: input,
                    site: .teardown,
                    group: &group,
                )
                guard case .completed = outcome, !Task.isCancelled else { return false }
                return true
            }
            guard tornDown else { return }
            // The relaunch is a fresh attempt: clear the memo so every launch
            // node re-runs over the torn-down state rather than being skipped
            // as "already done" from before the teardown.
            memo.removeAll()
            detachedFailures.removeAll()
            await runLaunchPlan(from: 0, input: ())
        }
        state = .running(reason: reason, task: task)
        await task.value
    }

    /// Cancel any in-flight drive, then drive the launch plan from
    /// `startIndex` on a fresh task, landing in `.ready` if the trunk
    /// completes. The new task drains the cancelled one before running, so
    /// two drives never overlap.
    private func drive(
        reason newReason: LifecycleReason,
        from startIndex: Int,
        input: any Sendable,
    ) async {
        let previous = currentTask
        previous?.cancel()
        phase = .launching
        failedResume = nil
        let task = Task { [weak self] in
            guard let self else { return }
            await previous?.value
            await runLaunchPlan(from: startIndex, input: input)
        }
        state = .running(reason: newReason, task: task)
        await task.value
    }

    /// Walk the launch trunk inside a task group (the group owns any detached
    /// children it spawns), publishing `.ready` with the trunk's output as
    /// soon as the trunk completes — *before* the children drain, which
    /// happens on scope exit. A superseded (cancelled) walk publishes nothing.
    private func runLaunchPlan(from startIndex: Int, input: any Sendable) async {
        await withDiscardingTaskGroup { group in
            let outcome = await self.walk(
                self.launchNodes,
                from: startIndex,
                input: input,
                site: .launch,
                group: &group,
            )
            guard case let .completed(value) = outcome, !Task.isCancelled else { return }
            self.phase = .ready(value as! Launch)
        }
    }

    /// The outcome of walking a trunk from some node onward.
    private enum WalkOutcome {
        /// Every applicable node finished; carries the trunk value after the
        /// last one.
        case completed(any Sendable)
        /// A node threw a non-cancellation error; `phase` is now `.failed`
        /// and `failedResume` points at the node.
        case failed
        /// The drive was superseded (cancelled); `phase` is left for the
        /// drive that cancelled it to set.
        case cancelled
    }

    /// Walk `nodes` from `startIndex`, threading the trunk value through
    /// steps and gates, spawning detached children into `group`, and honoring
    /// the memoized run-once set.
    private func walk(
        _ nodes: [LaunchPlanNode],
        from startIndex: Int,
        input: any Sendable,
        site: FailedResume.Site,
        group: inout DiscardingTaskGroup,
    ) async -> WalkOutcome {
        var value = input
        var index = startIndex
        while index < nodes.count {
            if Task.isCancelled { return .cancelled }

            switch nodes[index] {
                case let .step(node):
                    // Already finished this attempt (e.g. before an
                    // `enterForeground()` promotion re-drove from the top) —
                    // don't run it again; adopt its recorded output.
                    if let memoized = memo[node.id] {
                        value = memoized
                        break
                    }
                    // Only pass-through steps can carry a narrowed mode set
                    // (LaunchPlan preconditions the rest), so skipping here
                    // never leaves a hole in the data flow.
                    guard node.modes.contains(reason.modeSet) else { break }
                    let context = LifecycleStepContext(stepID: node.id, reason: reason)
                    phase = .running(context)
                    do {
                        let output = try await node.run(value, context)
                        memo[node.id] = output
                        value = output
                    } catch is CancellationError {
                        return .cancelled
                    } catch {
                        // A superseded drive can still throw a *real* error
                        // from its in-flight step (the work isn't required to
                        // be cancellation-responsive). The superseding drive
                        // owns `phase` now, so a dying drive must report
                        // `.cancelled` rather than clobber the new drive's
                        // state with `.failed` — the new drive re-runs the
                        // step and surfaces its own outcome.
                        guard !Task.isCancelled else { return .cancelled }
                        failedResume = FailedResume(site: site, index: index, input: value)
                        phase = .failed(LifecycleFailure(stepID: node.id, error: error))
                        return .failed
                    }

                case let .gate(node):
                    if memo[node.id] != nil { break }
                    guard node.modes.contains(reason.modeSet) else { break }
                    // A skipped gate is *not* memoized: `isNeeded` re-evaluates
                    // on the promotion re-drive, so a gate skipped headless
                    // still shows once the launch is user-visible.
                    guard await node.isNeeded(value) else { break }
                    if Task.isCancelled { return .cancelled }
                    let handle = LifecycleGateHandle(node: node, reason: reason, value: value)
                    phase = .awaitingGate(handle)
                    do {
                        try await handle.waitForResolution()
                        memo[node.id] = value
                    } catch is CancellationError {
                        return .cancelled
                    } catch {
                        guard !Task.isCancelled else { return .cancelled }
                        failedResume = FailedResume(site: site, index: index, input: value)
                        phase = .failed(LifecycleFailure(stepID: node.id, error: error))
                        return .failed
                    }

                case let .detached(children):
                    // Fan out and keep walking: children never block the trunk.
                    for child in children {
                        guard memo[child.id] == nil,
                              child.modes.contains(reason.modeSet) else { continue }
                        spawnDetached(child, value: value, group: &group)
                    }
            }
            index += 1
        }
        return .completed(value)
    }

    /// Run one detached child in `group`. Success is memoized (a re-drive
    /// doesn't repeat it); a real failure is recorded on `detachedFailures`
    /// — observable, never fatal; a failed child is *not* memoized, so the
    /// next re-drive retries it. A cancelled child (its drive was superseded)
    /// records nothing, mirroring the trunk's cancelled-is-not-failed rule.
    private func spawnDetached(
        _ child: DetachedNode,
        value: any Sendable,
        group: inout DiscardingTaskGroup,
    ) {
        let reason = reason
        // Formed as a main-actor `@Sendable` closure so it may capture the
        // (non-`Sendable`, main-actor-confined) node; the group task then
        // captures only this closure, which crosses safely.
        let operation: @Sendable @MainActor () async -> Void = { [weak self] in
            let context = LifecycleStepContext(stepID: child.id, reason: reason)
            do {
                try await child.run(value, context)
                self?.memo[child.id] = ()
            } catch is CancellationError {
                // Superseded drive draining — deliberately not a failure.
            } catch {
                guard !Task.isCancelled, let self else { return }
                detachedFailures.append(LifecycleFailure(stepID: child.id, error: error))
            }
        }
        group.addTask {
            await operation()
        }
    }
}

#if DEBUG
    extension LifecycleRunner {
        /// Injects a failure for SPI-enabled tests. Carries no resume point,
        /// so a subsequent `retry()` is a no-op.
        @_spi(Testing) public func injectFailureForTesting(_ failure: LifecycleFailure) {
            phase = .failed(failure)
        }
    }
#endif

// MARK: - Phase inspection

@MainActor
extension LifecycleRunner.Phase {
    public var isLaunching: Bool {
        if case .launching = self { true } else { false }
    }

    public var isReady: Bool {
        if case .ready = self { true } else { false }
    }

    /// The trunk's output, once the launch finished.
    public var readyValue: Launch? {
        if case let .ready(value) = self { value } else { nil }
    }

    /// The context of the currently running trunk step, if any.
    public var runningContext: LifecycleStepContext? {
        if case let .running(context) = self { context } else { nil }
    }

    /// The id of the currently running trunk step, if any.
    public var runningStepID: AnyHashable? {
        runningContext?.stepID
    }

    /// The handle of the gate the trunk is parked at, if any.
    public var gateHandle: LifecycleGateHandle? {
        if case let .awaitingGate(handle) = self { handle } else { nil }
    }

    /// The failure, if the launch failed.
    public var failure: LifecycleFailure? {
        if case let .failed(failure) = self { failure } else { nil }
    }

    /// Whether the step with `id` is the one currently running. Handy in
    /// tests that drive the runner until a particular step is active, and
    /// reads better than comparing the `AnyHashable` `runningStepID` to a
    /// raw token.
    public func isRunning(_ id: AnyHashable) -> Bool {
        runningStepID == id
    }

    /// Whether the trunk is parked at the gate with `id`.
    public func isAwaitingGate(_ id: AnyHashable) -> Bool {
        gateHandle?.id == id
    }

    /// Whether the launch failed in the node with `id`.
    public func failed(at id: AnyHashable) -> Bool {
        failure?.stepID == id
    }
}

@MainActor
extension LifecycleRunner.Phase {
    /// A value identity for the *surface* the container renders, so it can
    /// animate transitions between surfaces with `.animation(_:value:)` (the
    /// phase itself isn't `Equatable`).
    ///
    /// `launching` and `running` collapse to `.splash`: a step advancing
    /// keeps showing the splash, so it must not retrigger a top-level
    /// transition and flash it. Reaching a gate, `.failed`, or `.ready` is a
    /// real surface change and animates.
    package enum SurfaceIdentity: Hashable {
        case splash
        case gate(AnyHashable)
        case failed(AnyHashable)
        case ready
    }

    package var surfaceIdentity: SurfaceIdentity {
        switch self {
            case .launching, .running: .splash
            case let .awaitingGate(handle): .gate(handle.id)
            case let .failed(failure): .failed(failure.stepID)
            case .ready: .ready
        }
    }
}
