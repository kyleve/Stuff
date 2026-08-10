/// The presentation history that decides whether ready content is covered by
/// the splash. The deadline belongs to a rendered splash appearance—or, for
/// the opt-in policy, the first visible ready presentation when SwiftUI never
/// observed the runner's intervening splash phase.
enum LifecycleReadyRevealState: Equatable {
    case awaitingFirstVisibleReady
    case holdingSplash(until: ContinuousClock.Instant)
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
            case .revealed: true
        }
    }

    var splashHoldDeadline: ContinuousClock.Instant? {
        switch self {
            case let .holdingSplash(until: deadline): deadline
            case .awaitingFirstVisibleReady, .revealed: nil
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
}
