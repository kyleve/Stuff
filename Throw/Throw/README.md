# Throw (app target)

This target is the thin iOS shell for Throw. `AppDelegate` creates exactly one
`ThrowRuntime`; SwiftUI controller windows and UIKit-created external-display
windows all receive that runtime's shared ThrowUI session.

## Scene paths

- The iOS 26 scene manifest declares the controller and noninteractive
  external-display roles.
- iOS 27 controller hosting registers a retained external scene accessory,
  availability-gated at runtime.
- `ExternalDisplaySceneDelegate` hosts the production `ProjectionSurface` in
  a black `UIHostingController` and uses the connected `UIWindowScene`'s
  geometry.
- Preview and explicit full-screen mirroring fallback remain ThrowUI flows and
  use the same surface.

Output demand is reference-counted by stable IDs so connecting another window
does not create another poller. The runtime owns idle-timer restoration and
forwards app background/foreground transitions to the session.

## Resources

The app ships its app icon and generated software attribution report. Provider
attribution is separate user-facing copy in ThrowUI. The ADS-B Exchange key is
never an app resource or preference.

This target links ThrowUI directly and reaches ThrowCore transitively. Keeping
the composition shell off a second direct ThrowCore product avoids embedding a
duplicate static copy across the ThrowUI boundary.

## Build and test

Run the shared `Throw` scheme after `./ide --no-open`. App-shell tests are in
`ThrowTests`; domain and UI tests live with their modules. Revalidate the iOS
27 scene-accessory calls against the GM SDK before a release build.
