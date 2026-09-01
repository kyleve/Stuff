# Throw (app target)

This target is the thin iOS shell for Throw. `ThrowRuntime.swift` is the only
runtime construction owner. `AppDelegate` obtains exactly one live runtime.
SwiftUI controller windows and UIKit-created external-display windows all
receive that runtime's shared ThrowUI session.

Each scene composes its concrete ThrowUI root from that session. Runtime
handoff does not erase roots to `AnyView` or construct feature services.
The runtime starts one retained launch task when it creates the session.
Scene insertion, removal, and task cancellation cannot cancel this launch.

The session exposes one exhaustive launch state. Controller roots show loading,
onboarding, ready, or failed content from that state. Projection roots stay
black until the state contains loaded setup and credential status.

## Scene paths

- The iOS 26 scene manifest declares the controller and noninteractive
  external-display roles.
- Each controller root binds to its exact `UIWindowScene` and forwards that
  scene's foreground, background, and disconnect notifications to the shared
  runtime under a typed persistent identity.
- iOS 27 controller hosting registers a retained external scene accessory,
  availability-gated at runtime.
- `ExternalDisplaySceneDelegate` hosts `ThrowProjectionRootView` in a black
  `UIHostingController`. The root creates `ProjectionSurface` only after launch.
- Preview and explicit full-screen mirroring fallback remain ThrowUI flows and
  use the same surface.

Output demand is reference-counted by stable IDs so connecting another window
does not create another poller. The runtime owns idle-timer restoration and the
set of foreground controller-scene identities. The session is foreground while
that set is nonempty. External-display scenes provide output demand but never
stand in for a foreground controller.

When the final controller enters the background, the runtime starts a retained
preference flush under a UIKit execution lease. The runtime ends the lease when
the flush completes. Expiration cancels the retained task and ends the lease.
A returning controller also cancels the old task and lease. The next final
background transition starts a new flush generation.

## Resources

The app ships its app icon, generated software attribution report, and privacy
manifest. The manifest declares the required-reason use of `UserDefaults` for
Throw's app-only preferences. `PrivacyManifestTests` verifies the declaration
in the built app bundle. Provider attribution is separate user-facing copy in
ThrowUI. The ADS-B Exchange key is never an app resource or preference.

This target links ThrowUI directly and reaches ThrowCore transitively. Keeping
the composition shell off a second direct ThrowCore product avoids embedding a
duplicate static copy across the ThrowUI boundary.

## Build and test

Run the shared `Throw` scheme after `./ide --no-open`. App-shell tests are in
`ThrowTests`; domain and UI tests live with their modules. Revalidate the iOS
27 scene-accessory calls against the GM SDK before a release build.
