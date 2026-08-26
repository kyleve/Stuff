# ThrowUI

ThrowUI is Throw's SwiftUI presentation layer. It renders the controller,
setup and settings flows, calibration pattern, and the shared black projection
surface used by connected displays, full-screen fallback, and Preview.

## Quick start

Create one live `ThrowSession` at the application composition root, then pass
that same instance to every controller and output scene:

```swift
let session = ThrowSession.live()

ThrowRootView(session: session)
ProjectionSurface(session: session, presentation: .externalDisplay)
```

Scenes tell the session when an output begins and ends demanding projection
through `projectionOutputConnected(_:)` and
`projectionOutputDisconnected(_:)`. The app target remains responsible for
scene ownership and the idle timer.

## Architecture

`ThrowSession` is a `@MainActor` observable mirror over injected stores and
focused actors. `AirAndSpaceRuntime` owns aircraft polling, semantic Flights
frames, motion, and route enrichment. `ProjectionExperienceCoordinator` owns
selection, one rotation clock, prewarming, and lifecycle reconciliation. Every
scene observes the same coordinator and active experience.

Views render session state and send intents back to it. They never access
UserDefaults, Keychain, location, or the network. `ProjectionSurface` is the
sole renderer. It iterates the ordered layers in an immutable generic
`ProjectionFrame`. It does not enumerate a global catalog or special-case
Flights. The projector is decorative. Preview exposes the active experience
name, health, and one status summary.

The worker keeps independent animation, collision, correction, acquisition,
and static-line state for each experience. Prewarming prepares a complete
target frame without changing the visible frame. A switch fades the surface to
black, exchanges frames at black, and fades back in. Reduce Motion keeps this
opacity fade but removes experience-specific movement.

In Map mode, the surface draws cached geography before aircraft. Lines use
constant screen-space widths and a separate restrained intensity. Roads and
county boundaries remain dimmer than coastlines and major boundaries. True Sky
and quiet output remain free of geography.

Map settings store one fixed center for each coarse observer region. The map,
geography cache, and aircraft query use this center. Activity classification
and True Sky continue to use the observer location. The projection shows a dim
observer ring when the observer is inside the visible Map.

Aircraft activity cues use geometry and luminance without replacing airline
accents. The projection worker tracks acquisition rings, cue transitions,
airport-anchor fades, and completion pulses in memory. Reduce Motion removes
rings, pulses, scale changes, and moving corrections. Static phase geometry
and opacity changes remain.

The renderer uses fixed 30 Hz deadlines and skips elapsed slots after slow work.
Feed corrections preserve the previous projected velocity while their position residual decreases.
The correction reaches the new predicted path in 750 milliseconds.
Aggregate diagnostics record cadence, sample age, projected speed, correction distance, and snapshot overlap.

Map mode draws contextual airport centers and the longest open runway below
aircraft labels. True Sky draws aircraft cues without airport geometry.
Each source resolves route availability. FR24 resolves it in the position
response. The ADS-B sources resolve it through enrichment. Aircraft without an
origin and destination render at 35% opacity. Pending and failed lookups stay
primary. Callsign-only labels use the smaller detail typography reserved for
the callsign below a resolved route. These labels also use smaller collision
bounds.

The FR24 source settings page reads the saved token's 24-hour usage report.
The session caches this report for one minute to obey the provider's rate limit.
The page shows reported totals and cadence estimates. It does not treat these
values as an account balance. A usage-report rate limit is not shown as a
flight-position quota failure. A malformed usage report is scoped to this
estimate instead of implying that the live feed failed.

Appearance is resolved through `ThrowStylesheet` at `throwBroadwayRoot()`.
Preview and snapshot fixtures use memory-only dependencies and deterministic
frames.

The controller calls experiences “Views.” Root settings keep location,
calibration, master intensity, quiet hours, and About global. The Views screen
owns playlist order, dwell values, rotation, health, and experience setup. Air
& Space owns its source, mode, Map centers, layers, labels, marks, accents,
activity cues, and Geography intensity. Transit stays disabled until a provider
is implemented.

## Limitations

Throw's projection is ambient and non-safety-critical. The True Sky mode maps
direction and elevation to a dome; it does not optically register the image to
a particular eye point. Keystone and focus remain projector responsibilities.
