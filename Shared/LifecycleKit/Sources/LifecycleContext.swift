/// The handle a launch (or teardown) function drives its work through.
///
/// The function itself is ordinary async Swift — `let`s thread the data flow,
/// `if`s express conditionality, and the compiler holds the ordering (a value
/// cannot be used before the step that produced it). The context's wrappers
/// add exactly the engine concerns a bare function can't provide:
///
/// - **Phase publication**: each `step` publishes `.running(context)` while
///   its body runs; `gate` publishes `.awaitingGate(handle)` while parked.
/// - **Run-once memoization**: a completed step's output is recorded, so a
///   re-run of the function (an `enterForeground()` promotion) skips
///   completed work and returns the memoized value. This is why the one hard
///   rule of the function style exists: **all effects live inside
///   `step`/`gate`/`detached` — bare glue between calls re-runs on every
///   re-drive.**
/// - **Failure tagging**: a throw inside a step is attributed to that step's
///   ID in the resulting `.failed` phase.
///
/// Two invariants are held by API shape rather than runtime checks: only the
/// `Void`-returning `step` overload accepts `modes:` (a value-producing step
/// can't be skipped — and a plain `if` around one forces an `else` that also
/// produces the value), and `detached` bodies return `Void` (nothing can
/// depend on a fire-and-forget step).
///
/// Memo integrity is the function style's one discipline: a step ID must
/// identify a single call site. A duplicate ID traps on any complete walk of
/// the function (every test run), and a memo hit whose stored type doesn't
/// match the call site's traps with the offending ID.
@MainActor
public final class LifecycleContext {
    /// Why the app is launching, for vanilla branching in the function.
    public let reason: LifecycleReason

    /// The reporting context of the step currently running through this
    /// drive, so a step body can publish `progress`/`message` without
    /// threading a parameter: `context.runningStep?.message = "…"`.
    public private(set) var runningStep: LifecycleStepContext?

    private let memo: LifecycleMemo
    private let recordExecuted: @MainActor (AnyHashable) -> Void
    private let publishRunning: @MainActor (LifecycleStepContext) -> Void
    private let publishGate: @MainActor (LifecycleGateHandle) -> Void
    private let recordDetachedFailure: @MainActor (LifecycleFailure) -> Void

    /// IDs visited by this walk of the function, so a duplicate — two call
    /// sites sharing an ID, which would corrupt the memo — traps on any
    /// complete run rather than silently skipping the second site.
    private var visited: Set<AnyHashable> = []

    /// The fire-and-forget tasks this walk spawned. Unstructured (the
    /// function must be able to return while they run), so the runner drains
    /// them explicitly after the function — cancelling them first when the
    /// drive was superseded.
    private var detachedTasks: [Task<Void, Never>] = []

    init(
        reason: LifecycleReason,
        memo: LifecycleMemo,
        recordExecuted: @escaping @MainActor (AnyHashable) -> Void,
        publishRunning: @escaping @MainActor (LifecycleStepContext) -> Void,
        publishGate: @escaping @MainActor (LifecycleGateHandle) -> Void,
        recordDetachedFailure: @escaping @MainActor (LifecycleFailure) -> Void,
    ) {
        self.reason = reason
        self.memo = memo
        self.recordExecuted = recordExecuted
        self.publishRunning = publishRunning
        self.publishGate = publishGate
        self.recordDetachedFailure = recordDetachedFailure
    }

    /// Run a required, value-producing step. Deliberately no `modes:`
    /// parameter — a producer can't be skipped, or downstream code would
    /// have no value; gate on the launch reason only around `Void` work.
    ///
    /// Memoized per attempt: a re-run of the function (an `enterForeground()`
    /// promotion) returns the recorded output without running `body` again. A
    /// throw fails the drive at `id` — terminally, since there is no retry.
    public func step<Output: Sendable>(
        _ id: AnyHashable,
        _ body: @MainActor () async throws -> Output,
    ) async throws -> Output {
        try await run(id, body)
    }

    /// Run a required, `Void`-output step — the only trunk step that may
    /// gate on the launch reason (`modes`), because skipping it can't leave
    /// a hole in the data flow. Skipped steps are not memoized, so they run
    /// when a promotion re-drives the function under the new reason.
    public func step(
        _ id: AnyHashable,
        modes: LifecycleModeSet = .all,
        _ body: @MainActor () async throws -> Void,
    ) async throws {
        guard modes.contains(reason.modeSet) else { return }
        try await run(id, body)
    }

    /// Park the drive at `gate`, publishing a `LifecycleGateHandle` (carrying
    /// `value` for the UI registry) and suspending until the gate's view
    /// resolves it. Conditionality is the caller's plain `if`; the gate's
    /// `modes` (default `.foreground`) skip it on headless drives, unmemoized,
    /// so the promotion re-run parks. Completion is memoized; `fail(_:)`
    /// fails the drive at the gate's ID.
    public func gate<G: LifecycleGate>(_ gate: G, value: G.Value) async throws {
        try Task.checkCancellation()
        visit(gate.id)
        guard memo.value(for: gate.id) == nil else { return }
        guard gate.modes.contains(reason.modeSet) else { return }

        let handle = LifecycleGateHandle(
            id: gate.id,
            reason: reason,
            gateType: ObjectIdentifier(G.self),
            value: value,
        )
        publishGate(handle)
        do {
            try await handle.waitForResolution()
            memo.set((), for: gate.id)
            recordExecuted(gate.id)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard !Task.isCancelled else { throw CancellationError() }
            throw LifecycleStepFailure(id: gate.id, underlying: error)
        }
    }

    /// Spawn fire-and-forget work: runs concurrently with the rest of the
    /// function, never blocks `.ready`, and a failure lands on
    /// `LifecycleRunner.detachedFailures` (observable, never fatal; the
    /// failed child is unmemoized, so the next re-drive retries it). Success
    /// is memoized, so re-drives don't repeat it. The runner drains spawned
    /// work after the function returns — before a teardown's relaunch — and
    /// cancels it when the drive is superseded.
    public func detached(
        _ id: AnyHashable,
        modes: LifecycleModeSet = .all,
        _ body: @escaping @Sendable @MainActor () async throws -> Void,
    ) {
        visit(id)
        guard memo.value(for: id) == nil else { return }
        guard modes.contains(reason.modeSet) else { return }

        recordExecuted(id)
        let memo = memo
        let recordDetachedFailure = recordDetachedFailure
        detachedTasks.append(Task { @MainActor in
            do {
                try await body()
                memo.set((), for: id)
            } catch is CancellationError {
                // Superseded drive draining — deliberately not a failure.
            } catch {
                guard !Task.isCancelled else { return }
                recordDetachedFailure(LifecycleFailure(stepID: id, error: error))
            }
        })
    }

    // MARK: - Engine side

    private func run<Output: Sendable>(
        _ id: AnyHashable,
        _ body: @MainActor () async throws -> Output,
    ) async throws -> Output {
        try Task.checkCancellation()
        visit(id)
        if let memoized = memo.value(for: id) {
            guard let output = memoized as? Output else {
                preconditionFailure(
                    """
                    Step '\(id)' memoized \(type(of: memoized)) but this call \
                    site expects \(Output.self) — two call sites are sharing \
                    one step ID.
                    """,
                )
            }
            return output
        }

        let stepContext = LifecycleStepContext(stepID: id, reason: reason)
        runningStep = stepContext
        defer { runningStep = nil }
        publishRunning(stepContext)
        do {
            let output = try await body()
            memo.set(output, for: id)
            recordExecuted(id)
            return output
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A superseded drive can still throw a *real* error from its
            // in-flight step (the work isn't required to be cancellation-
            // responsive). The superseding drive owns the phase now, so a
            // dying drive must report cancellation rather than fail the
            // drive that replaced it.
            guard !Task.isCancelled else { throw CancellationError() }
            throw LifecycleStepFailure(id: id, underlying: error)
        }
    }

    private func visit(_ id: AnyHashable) {
        precondition(
            visited.insert(id).inserted,
            "Step ID '\(id)' was used twice in one walk — each step ID must identify a single call site.",
        )
    }

    /// Cancel this walk's fire-and-forget tasks. Called by the runner when
    /// the drive was superseded, before draining — unstructured tasks don't
    /// inherit the drive's cancellation.
    func cancelDetached() {
        for task in detachedTasks {
            task.cancel()
        }
    }

    /// Await every fire-and-forget task this walk spawned. Called by the
    /// runner *after* publishing the terminal phase (children never block
    /// `.ready`) and before a teardown's relaunch (no torn-down-world work
    /// overlaps the fresh launch). Cancellation-aware: a drive superseded
    /// mid-drain cancels the children rather than hanging behind them.
    func drainDetached() async {
        let tasks = detachedTasks
        if Task.isCancelled {
            for task in tasks {
                task.cancel()
            }
        }
        await withTaskCancellationHandler {
            for task in tasks {
                await task.value
            }
        } onCancel: {
            for task in tasks {
                task.cancel()
            }
        }
    }
}

/// The per-site (launch vs. teardown) run-once store: each completed node's
/// output, keyed by ID. A class so the runner and the drive's context share
/// one instance; separate instances per site, so launch and teardown IDs
/// can't collide across walks.
@MainActor
final class LifecycleMemo {
    private var values: [AnyHashable: any Sendable] = [:]

    func value(for id: AnyHashable) -> (any Sendable)? {
        values[id]
    }

    func set(_ value: any Sendable, for id: AnyHashable) {
        values[id] = value
    }

    func removeAll() {
        values.removeAll()
    }
}

/// A step/gate body's error, tagged with the node it failed in so the runner
/// can attribute the `.failed` phase. Internal — the runner unwraps it into
/// a `LifecycleFailure`.
struct LifecycleStepFailure: Error {
    let id: AnyHashable
    let underlying: Error
}

/// The failure ID used when a launch/teardown function throws *outside* any
/// `step` — bare glue failed. Effects (and throws) should live inside steps;
/// this exists so even undisciplined failures stay attributable.
public enum LifecycleFunctionID: Hashable, Sendable {
    case launch
    case teardown
}
