# ThrowUI

ThrowUI is Throw's SwiftUI presentation layer. It renders the controller,
setup and settings flows, calibration pattern, and the shared black projection
surface used by connected displays, full-screen fallback, and Preview.

## Quick start

Create one live `ThrowSession` at the application composition root, then pass
that same instance to every controller and output scene:

```swift
let session = ThrowSession.live()
session.startLaunch()

ThrowRootView(session: session)
ThrowProjectionRootView(session: session, presentation: .externalDisplay)
```

Scenes tell the session when an output begins and ends demanding projection
through `projectionOutputConnected(_:)` and
`projectionOutputDisconnected(_:)`. The app target remains responsible for
scene ownership and the idle timer. Its process runtime also injects whether
at least one controller scene is foreground. External-display scenes contribute
output demand but do not contribute controller foreground presence.

## Architecture

`ThrowSession` is a `@MainActor` observable facade over injected stores and
focused actors. `AirAndSpaceRuntime` owns aircraft polling, semantic Flights
frames, motion, and route enrichment. `ProjectionExperienceCoordinator` owns
selection, one rotation clock, prewarming, and lifecycle reconciliation. Its
validated runtime state keeps the active identity inside the current playlist,
including when startup replaces the empty default with saved settings. Every
scene observes the same coordinator and active experience.

Cold launch has one exhaustive process state. Loading carries no setup.
Onboarding carries `ThrowOnboardingSetup`, and ready carries
`ThrowConfiguredSetup`. A failed state identifies preference or credential
access. A missing credential is loaded data, not a storage error.

The session retains one launch task. All callers join that task, and caller
cancellation does not cancel it. The task loads preferences and both credential
states before it publishes onboarding or ready. It never replaces a load error
with default preferences.

Launch also starts one independent durable-logging task. Its typed state
distinguishes unavailable fixtures, opening, ready, and failed storage. A log
store failure does not fail the product launch because OSLog remains active.

Cold-launch failure views show localized recovery text. Typed session logs keep
the failed boundary and attach the underlying storage error for diagnostics.

Software attribution has one typed load state. An empty report remains loaded.
A manifest error shows an unavailable state. Diagnostics receive the underlying
error only after the durable logging starter begins its work.

Post-launch failures use one typed ledger with one entry per operation owner.
An operation success clears only its entry. Other failures remain visible.
Views show localized recovery text, while typed session logs attach the
underlying error. The UI does not store or render raw error descriptions.

`ThrowSession+Composition.swift` is the only live construction boundary. It
creates the stores, durable-logging starter, aircraft source graph, poller, and
session once. Previews and tests use the fixture path in that same file.

The coordinator issues one `ProjectionActivationLease` for each View activation.
The lease carries both the View identity and its monotonic generation through
activation, deactivation, prepared-frame, and visible-count work. The runtime
accepts teardown only for its active lease, so a queued disconnect cannot stop a
replacement activation. Runtime-local counters invalidate work across suspension
without minting coordinator identities. Location refreshes also recheck their
generation after the last accumulator read. Playlist configurations carry
monotonic session revisions. The coordinator rejects an older value that arrives
late.
The session publishes visible output as one closed `ProjectionPresentationState`.
Its Air & Space and Transit cases bind coordinator identity to matching typed output.
Each rendered case stores its semantic frame, activation generation, renderer frame, effects,
observer point, Geography health, and complete projection context. Public accessors
derive from that value. Output count derives from the output-demand set.

Coordinator intents use a lossless command stream. Each timer path rechecks
its playlist revision, active identity, demand, and runtime generation after a
clock read. Pause has no effect without projection demand.

Connection tests and provider usage reports go through the injected
`AircraftSourceOperationServing` boundary. ThrowUI does not construct or
downcast concrete provider sources.
Each tested source candidate retains its closed Core validation draft. A local
source cannot carry a replacement credential into the apply transaction.

Views render session state and send intents back to it. They never access
UserDefaults, Keychain, location, or the network. `ProjectionSurface` is the
sole renderer. It iterates the ordered layers in an immutable renderer
`ProjectionFrame`. It does not enumerate a global catalog or special-case
Flights. The projector is decorative. Preview exposes the active experience
name, health, and one status summary.

The session stores validated `ThrowGlobalPreferences` and
`AirAndSpacePreferences` values. Its scalar properties are read-only display
projections. Settings keep raw control drafts locally and publish only complete,
validated replacements. An invalid draft cannot change polling or persistence.
Onboarding uses the same aggregates and keeps calibration preview state separate.
Quiet-wake actions pass a `TemporaryQuietWake` value through the session
boundary. Unsupported minute counts cannot enter the runtime.

The worker keeps independent animation, collision, correction, and acquisition
state for each experience. Its static-line projections use a bounded cache of
recent layer, center, viewport, and calibration keys. Prewarming binds a
complete typed request to one activation generation. A successful provider
response is not ready until that exact generation has a prepared frame. A
switch fades the surface to black and commits the coordinator with that request.
This commit is one assignment. The fade state buffers newer target output until
fade-in completes. Reduce Motion keeps this fade but removes experience movement.

The production worker accepts one typed `ProjectionFrameRequest`. This request
stores its semantic input, revision, observer, map center, calibration, and motion setting.
Core projects static lines, then creates one closed
`PreparedProjectionExperienceInput`. Each cached static-line frame retains its
semantic revision and projection context. `ProjectionEngine` rejects stale or
mismatched prepared lines and returns the matching `ProjectedExperienceFrame`.
This value fixes each experience's valid projected layers and modes.
`ProjectionFrame.swift` erases it once into renderer layers. Raw construction
and replacement stay in that file. A closed presentation identity separates
Air & Space, Transit, and DEBUG frames before any animation combines them.
Before publication, the session compares the result with its current complete request.
A semantic or context change invalidates the old result. The surface reads one
visible projection value per render pass. Test-only raw worker entry points are
absent from release builds.

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

Source and credential changes have one commit point. Throw prepares Keychain
and preference writes before it drains the live source. A storage failure keeps
the prior source, credential state, feed health, and projection active.

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
