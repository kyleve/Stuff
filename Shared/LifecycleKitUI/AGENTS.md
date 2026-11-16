# LifecycleKitUI — Presentation contracts

Read the [repository contract](../../AGENTS.md). The [README](README.md) owns the API.

Use SwiftUI, LifecycleKit, and SFSafeSymbols only. App-specific launch UI belongs to consumers.
Keep view construction here and renderable engine state in LifecycleKit.

## Invariants

- Build content only from `.ready`'s carried value, including under a splash hold that warms the destination.
  Keep one content call site so reveal does not change SwiftUI identity.
- Build no view tree when `reason.buildsNoViewTree`, even at `.ready`.
- Resolve all splash-showing states to one `LaunchOverlay.splash` case; phase-specific branches remount animations and caption timers.
- A positive `minimumSplashDuration` covers the first visible ready reveal, including an already-ready mount.
  Key the hold on readiness and active-scene visibility; retain an observed splash's original deadline. Never arm or complete it offscreen. Zero reveals immediately.
- An interrupted first reveal returns to awaiting. Only an uncovered frame already committed survives resume without replay.
  Guards: `positiveMinimumCoversAlreadyReadyContent`, `positiveMinimumKeepsBackgroundReadyHeadless`, `promotedBackgroundReadyForcesTheFirstRevealSplash`, `interruptedFirstRevealWaitsAgainAfterTheSceneBecomesActive`.
- Assert reveal through the absent splash; content also exists during the hold.
  `isShowingSplash` reads the runner's surface, never `displayedSurfaceIdentity`, which would re-arm the hold from its own release.
- Resolve gates through their own handles so superseded drives no-op. Allow one registration per gate type.
- A missing gate registration logs to OSLog (`com.stuff.lifecyclekitui`) and fails the handle with `MissingGateViewError`.
  Keep failure terminal; never leave an indefinite splash or add a retry surface.

## Testing

Use hosted `LifecycleKitUITests` in [Tests](Tests) for rendered branches and connected/disconnected proxy behavior.
Engine behavior belongs to LifecycleKit's tests.
