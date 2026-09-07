# Throw app – Module Shape

The Throw app is the iOS composition and scene shell; see
[`README.md`](README.md). Read the root [`AGENTS.md`](../../AGENTS.md) and group
[`../AGENTS.md`](../AGENTS.md) first.

## Scope and invariants

- Depend directly on ThrowUI only, reaching ThrowCore through that product.
  Keep domain, provider, persistence, and presentation behavior out of this
  target.
- Expose the shared session through the runtime protocol. Compose concrete
  controller and projection roots at each scene without `AnyView` erasure.
- Construct `ThrowRuntime` only in `ThrowRuntime.swift`. `AppDelegate` obtains
  that one live runtime. Never create a fallback runtime.
- Start cold launch from the process runtime. Never attach launch ownership to a
  scene or SwiftUI task.
- Compose controller and projection surfaces through the exhaustive session
  launch state. Render no configured surface before the ready case.
- Track foreground controller scenes by their typed session identities in the
  process runtime. Derive session foreground presence from the nonempty set;
  external-display scenes never join it.
- Retain the final-background preference flush under one injected UIKit
  execution lease. End the lease on completion or expiration. Cancel the
  retained flush task when the lease expires or a controller returns foreground.
- Host every projected output with ThrowUI's `ThrowProjectionRootView`. Keep its
  surface opaque black.
- Attach the iOS 27 `ExternalNonInteractiveAccessory` to the controller root.
  Never construct another runtime or session in the accessory content.
- Keep required-reason API declarations in `PrivacyInfo.xcprivacy`. Preserve
  the built-app manifest guard when changing app resources or preferences.
- Restore the process's prior idle-timer state when the final output leaves.

## Testing

Run `./test ThrowTests`. App tests prove the shared runtime, controller-scene
lifecycle, output demand, background flush, and idle-timer contracts.
