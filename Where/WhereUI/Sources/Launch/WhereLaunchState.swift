import Foundation
import Observation
import WhereCore

/// The observable launch state `RootView` renders — the app-owned remnant of
/// the lifecycle engine, now that launch is one raw async task
/// (`WhereLaunch.run`).
///
/// One `Phase` value models the whole surface machine (the modeling-state
/// convention: no `isLoading` + `error` + `session` triple), and `.ready`
/// carries the session, so the app surface still cannot be built without the
/// value the launch produced. Scene activation is a *park signal* rather
/// than a re-drive: the launch task awaits `whenSceneActive()` before its
/// foreground-only tail, so promotion is structural — nothing runs twice,
/// and there is no memoization.
///
/// Failure is terminal by design (no retry): transiently retryable work
/// belongs to the layer that understands it, and the recovery for anything
/// else is relaunching the app.
@MainActor
@Observable
public final class WhereLaunchState {
    /// The launch surface machine. Each case carries exactly what its
    /// surface needs.
    public enum Phase {
        /// The launch task is working (or parked pre-onboarding) — splash.
        case launching
        /// Parked on first-run onboarding; the view resolves the handle.
        case onboarding(OnboardingHandle, WhereSession)
        /// The launch failed. Terminal: the surface offers no retry.
        case failed(any Error)
        /// Launch finished — hand the session to the app's main UI.
        case ready(WhereSession)
    }

    /// The single value `RootView` renders.
    public private(set) var phase: Phase = .launching

    /// Whether a scene has ever been genuinely active this process. Until it
    /// is, `RootView` builds no view tree (the raw-async analog of the old
    /// `buildsNoViewTree`: a headless wake's scene may be connected without
    /// being shown) and the launch task stays parked before its
    /// foreground-only tail.
    public private(set) var sceneHasBeenActive = false

    /// Waiters parked in `whenSceneActive()` — the launch task, in practice.
    @ObservationIgnored private var activationWaiters:
        [CheckedContinuation<Void, Error>] = []

    /// The current attempt's launch task. Reset cancels and drains it before
    /// erasing, then begins a fresh attempt.
    @ObservationIgnored private var launchTask: Task<Void, Never>?

    /// Fire-and-forget fan-out spawned by the current attempt (reminder /
    /// summary / widget configuration), tracked so a reset can cancel and
    /// drain it — no torn-down-world work may overlap the fresh attempt.
    @ObservationIgnored private var fanTasks: [Task<Void, Never>] = []

    /// How to run one launch attempt, retained by `WhereLaunch.start` so a
    /// reset can begin a fresh attempt with the same composition (model,
    /// bootstrap, `onServicesReady`) without re-threading it through
    /// Settings.
    @ObservationIgnored var runAttempt: (@MainActor () async -> Void)?

    public init() {}

    /// Mark the scene active and resume anything parked on it. Idempotent;
    /// called by `RootView` when `scenePhase` becomes `.active`. Never
    /// un-set: once a human has seen the app, the launch tail may run.
    public func sceneBecameActive() {
        guard !sceneHasBeenActive else { return }
        sceneHasBeenActive = true
        let waiters = activationWaiters
        activationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Park until a scene is genuinely active — the promotion point in
    /// `WhereLaunch.run`. Everything above the park services a headless
    /// wake; everything below needs a visible scene. Cancellation-aware, so
    /// a reset can drain an attempt parked here.
    func whenSceneActive() async throws {
        guard !sceneHasBeenActive else { return }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                if sceneHasBeenActive {
                    continuation.resume()
                } else {
                    activationWaiters.append(continuation)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let waiters = activationWaiters
                activationWaiters.removeAll()
                for waiter in waiters {
                    waiter.resume(throwing: CancellationError())
                }
            }
        }
    }

    // MARK: - Attempt lifecycle (driven by WhereLaunch)

    /// Publish a new phase. Callers guard cancellation first: a cancelled
    /// (superseded) attempt must not write over the phase the reset now owns.
    func publish(_ phase: Phase) {
        self.phase = phase
    }

    /// Start a fresh attempt task running the retained `runAttempt`.
    func beginAttempt() {
        launchTask = Task { @MainActor [weak self] in
            await self?.runAttempt?()
        }
    }

    /// Spawn fire-and-forget work owned by the current attempt: it never
    /// blocks the phase reaching `.ready`, but a reset drains it before the
    /// fresh attempt begins.
    func spawnFan(_ body: @escaping @Sendable @MainActor () async -> Void) {
        fanTasks.append(Task { @MainActor in await body() })
    }

    /// Cancel the in-flight attempt and its fan, and await both draining —
    /// the reset's first move, so no superseded work overlaps the erase or
    /// the fresh attempt.
    func cancelAndDrainAttempt() async {
        launchTask?.cancel()
        let fan = fanTasks
        fanTasks.removeAll()
        for task in fan {
            task.cancel()
        }
        await launchTask?.value
        for task in fan {
            await task.value
        }
        launchTask = nil
    }
}

// MARK: - Phase inspection

@MainActor
extension WhereLaunchState.Phase {
    public var isLaunching: Bool {
        if case .launching = self { true } else { false }
    }

    public var isReady: Bool {
        if case .ready = self { true } else { false }
    }

    /// The session, once the launch finished.
    public var readyValue: WhereSession? {
        if case let .ready(session) = self { session } else { nil }
    }

    /// The parked onboarding handle + session, while onboarding shows.
    public var onboarding: (handle: OnboardingHandle, session: WhereSession)? {
        if case let .onboarding(handle, session) = self { (handle, session) } else { nil }
    }

    /// The failure, if the launch failed (terminal).
    public var failure: (any Error)? {
        if case let .failed(error) = self { error } else { nil }
    }

    /// A value identity for the *surface* `RootView` renders, so transitions
    /// animate on real surface changes (the phase itself isn't `Equatable`)
    /// and never re-trigger while the same surface stays up.
    enum SurfaceIdentity: Hashable {
        case splash
        case onboarding
        case failed
        case ready
    }

    var surfaceIdentity: SurfaceIdentity {
        switch self {
            case .launching: .splash
            case .onboarding: .onboarding
            case .failed: .failed
            case .ready: .ready
        }
    }
}
