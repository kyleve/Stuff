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

`ThrowSession` is a `@MainActor` observable mirror over the injected ThrowCore
stores and polling actor. Views render its state and send intents back to it;
they never access UserDefaults, Keychain, location, or the network directly.
`ProjectionSurface` is the sole renderer. It draws immutable
`ProjectionFrame` values and has presentation-specific accessibility only—the
projector is decorative, while Preview exposes one status summary.
The controller enumerates `LayerCatalog` descriptors instead of maintaining a
second layer roster. Projection invokes the catalog's typed Flights and
Geography runtimes. Runtime type erasure does not enter the rendering pipeline.
In Map mode, the surface draws cached geography before aircraft. Lines use
constant screen-space widths and a separate restrained intensity. Roads and
county boundaries remain dimmer than coastlines and major boundaries. True Sky
and quiet output remain free of geography.

Aircraft activity cues use geometry and luminance without replacing airline
accents. The projection worker tracks acquisition rings, cue transitions,
airport-anchor fades, and completion pulses in memory. Reduce Motion removes
rings, pulses, scale changes, and moving corrections. Static phase geometry
and opacity changes remain.

Map mode draws contextual airport centers and the longest open runway below
aircraft labels. True Sky draws aircraft cues without airport geometry.

Appearance is resolved through `ThrowStylesheet` at `throwBroadwayRoot()`.
Preview and snapshot fixtures use memory-only dependencies and deterministic
frames.

## Limitations

Throw's projection is ambient and non-safety-critical. The True Sky mode maps
direction and elevation to a dome; it does not optically register the image to
a particular eye point. Keystone and focus remain projector responsibilities.
