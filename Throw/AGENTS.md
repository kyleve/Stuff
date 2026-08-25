# Throw – Feature Shape

Throw is an iPhone/iPad ceiling-projection app; see [`README.md`](README.md).
This file complements the root [`AGENTS.md`](../AGENTS.md), which owns build,
formatting, and repository-wide conventions.

## Modules and layering

The dependency direction is **ThrowCore → ThrowUI → Throw app**. Put domain
values, projection, sources, polling, persistence seams, and schedules in
ThrowCore. Put observable presentation state and SwiftUI/UIKit presentation in
ThrowUI. Keep the app target a scene and composition shell. Never import
WhereCore, RegionKit, or LifecycleKit into this feature.

## Invariants

- Create one `ThrowRuntime` in the app delegate and inject its one
  `ThrowSession` into every scene. A scene delegate must never create services.
- Select exactly one aircraft source. Cancel and drain it before starting
  another; never combine or automatically fall back between providers.
- Render Preview, full-screen fallback, and external displays with the same
  `ProjectionSurface`.
- Keep secrets in `AircraftCredentialStore` only. Never persist or log a key,
  observer coordinate, receiver URL, request URL, aircraft identity, or
  response body.
- Keep the external surface opaque black and noninteractive. Calibration may
  bypass quiet output without starting a feed.
- Keep Geography offline and Map-only. Never add online map tiles or transmit
  the observer location to a map provider.
- Revalidate the availability-gated iOS 27 scene-accessory adapter against the
  GM SDK before release.

## Installing to a device

`./Throw/install` builds, signs, installs, and launches Throw on a connected
iPhone or iPad. It is macOS-only. Configure the signing team once with
`./ide --team-id <id>`. Run `./Throw/install --help` for all options.

## Testing

Use `./test ThrowCoreTests`, `./test ThrowUITests`, and `./test ThrowTests` for
focused coverage. Throw's image bundle joins the shared `StuffSnapshotTests`
scheme; do not add a separate snapshot scheme.
