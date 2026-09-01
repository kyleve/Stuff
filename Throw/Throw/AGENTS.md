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
  that one live runtime. Scene delegates use the platform handoff and never create a fallback.
- Host every projected output with ThrowUI's `ProjectionSurface`; keep its
  UIKit window and hosting view opaque black.
- Derive size and aspect changes from the connected `UIWindowScene`, never
  `UIScreen.main`.
- Retain the iOS 27 `UISceneAccessory` and its registration for as long as the
  controller scene is eligible. Revalidate this adapter against the GM SDK.
- Keep required-reason API declarations in `PrivacyInfo.xcprivacy`. Preserve
  the built-app manifest guard when changing app resources or preferences.
- Restore the process's prior idle-timer state when the final output leaves.

## Testing

Run `./test ThrowTests`. App tests prove the delegate and every scene handoff
use the same runtime and that duplicate output IDs do not duplicate demand.
