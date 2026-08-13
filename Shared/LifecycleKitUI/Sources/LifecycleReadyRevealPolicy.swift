/// Controls how `LifecycleContainer` presents its first foreground-visible
/// `.ready` value.
public enum LifecycleReadyRevealPolicy: Sendable, Hashable {
    /// Let the runner's rendered phases drive presentation. An already-ready
    /// container reveals immediately when no splash appearance established a
    /// minimum-duration hold.
    case phaseDriven

    /// Show the splash before the first visible ready-content reveal, even when
    /// a headless-to-foreground drive completes between SwiftUI render passes.
    /// The splash uses the container's `minimumSplashDuration`.
    case splashBeforeFirstReveal
}
