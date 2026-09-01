# Throw (app target)

This target is the thin iOS shell for Throw. `ThrowRuntime.swift` is the only
runtime construction owner. `AppDelegate` obtains exactly one live runtime.
SwiftUI controller windows and UIKit-created external-display windows all
receive that runtime's shared ThrowUI session.

Each scene composes its concrete ThrowUI root from that session. Runtime
handoff does not erase roots to `AnyView` or construct feature services.

## Scene paths

- The iOS 26 scene manifest declares the controller and noninteractive
  external-display roles.
- Each controller root binds to its exact `UIWindowScene` and forwards that
  scene's foreground, background, and disconnect notifications to the shared
  runtime under a typed persistent identity.
- iOS 27 controller hosting registers a retained external scene accessory,
  availability-gated at runtime.
- `ExternalDisplaySceneDelegate` hosts the production `ProjectionSurface` in
  a black `UIHostingController` and uses the connected `UIWindowScene`'s
  geometry.
- Preview and explicit full-screen mirroring fallback remain ThrowUI flows and
  use the same surface.

Output demand is reference-counted by stable IDs so connecting another window
does not create another poller. The runtime owns idle-timer restoration and the
set of foreground controller-scene identities. The session is foreground while
that set is nonempty. External-display scenes provide output demand but never
stand in for a foreground controller.

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
