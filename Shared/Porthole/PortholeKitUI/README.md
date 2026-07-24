# PortholeKitUI

PortholeKitUI is the on-device pairing/status UI for [Porthole](../), styled with
[Broadway](../../Broadway). Drop `PortholePairingView` into a developer menu to
start/stop advertising, show the pending pairing code, list paired Macs (swipe to
revoke), and see the active session count.

## Using it

```swift
import PortholeKitUI

// `porthole` is your app's Porthole instance (see PortholeKit)
NavigationLink("Porthole") {
    PortholePairingView(porthole: porthole)
}
```

The view seeds its own Broadway root (`portholeBroadwayRoot()`), so it styles
correctly whether or not the host app has a Broadway root of its own. Gate it
behind `#if DEBUG` — it's a developer surface.

## Design system

Appearance tokens live in `PortholeStylesheet` (a Broadway `BStylesheet`), read
via `@Environment(\.stylesheet)`; off the `View` tree use
`PortholeStylesheet.default`. Most tokens are fixed; the pairing-code face widens
its tracking at accessibility Dynamic Type sizes.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholeKitUITests`). Pins the default tokens and the environment fallback, and
hosts a probe (via `TestHostSupport`) to confirm the trait-aware token resolves
across the PortholeKitUI↔BroadwayUI boundary, plus a `PortholePairingView`
render smoke test. Broadway is reached transitively through PortholeKitUI — the
test bundle does not re-link it.
