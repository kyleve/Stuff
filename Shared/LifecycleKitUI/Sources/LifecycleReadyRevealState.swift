/// The presentation history that decides whether ready content is covered by
/// the splash. The deadline belongs to a rendered splash appearance—or, for
/// the opt-in policy, the first visible ready presentation when SwiftUI never
/// observed the runner's intervening splash phase.
enum LifecycleReadyRevealState: Equatable {
    case awaitingFirstVisibleReady
    case holdingSplash(until: ContinuousClock.Instant)
    /// The deadline elapsed and the overlay may leave, but SwiftUI has not yet
    /// committed an uncovered ready-content frame.
    case releasing
    case revealed

    init(
        policy: LifecycleReadyRevealPolicy,
        minimumSplashDuration: Duration,
    ) {
        switch policy {
            case .phaseDriven:
                self = .revealed
            case .splashBeforeFirstReveal:
                self = minimumSplashDuration > .zero ? .awaitingFirstVisibleReady : .revealed
        }
    }

    var canRevealReady: Bool {
        switch self {
            case .awaitingFirstVisibleReady, .holdingSplash: false
            case .releasing, .revealed: true
        }
    }

    var splashHoldDeadline: ContinuousClock.Instant? {
        switch self {
            case let .holdingSplash(until: deadline): deadline
            case .awaitingFirstVisibleReady, .releasing, .revealed: nil
        }
    }

    mutating func splashAppeared(
        at instant: ContinuousClock.Instant,
        minimumSplashDuration: Duration,
    ) {
        guard minimumSplashDuration > .zero else {
            self = .revealed
            return
        }
        self = .holdingSplash(until: instant.advanced(by: minimumSplashDuration))
    }

    mutating func readyBecameVisible(
        at instant: ContinuousClock.Instant,
        minimumSplashDuration: Duration,
    ) {
        guard case .awaitingFirstVisibleReady = self else { return }
        splashAppeared(at: instant, minimumSplashDuration: minimumSplashDuration)
    }

    mutating func splashHoldElapsed() {
        guard case .holdingSplash = self else { return }
        self = .releasing
    }

    mutating func contentDidReveal() {
        guard case .releasing = self else { return }
        self = .revealed
    }

    /// Cancels an unrevealed presentation episode when its scene stops being
    /// visible. The opt-in policy still owes a splash on the next active
    /// presentation; the default policy returns to its immediate-ready state.
    mutating func sceneBecameInactive(
        beforeFirstRevealUsing policy: LifecycleReadyRevealPolicy,
    ) {
        guard case .revealed = self else {
            switch policy {
                case .phaseDriven:
                    self = .revealed
                case .splashBeforeFirstReveal:
                    self = .awaitingFirstVisibleReady
            }
            return
        }
    }
}
