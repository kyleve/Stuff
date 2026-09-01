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

- Construct `ThrowRuntime` only in `ThrowRuntime.swift`. Construct the live
  `ThrowSession` and its live dependencies only in `ThrowSession+Composition.swift`.
  Inject those objects into every scene.
- Start one retained cold-launch task from the process runtime. Gate every root
  on the session's exhaustive launch state.
- Keep the View catalog compile-time. Use `ProjectionExperience` in code and
  “View” in user-facing text. Never add runtime plugins or `AnyView` boundaries.
- Keep planned View IDs at display and persistence boundaries. Pass only a
  `RunnableProjectionExperienceID` to playlist and runtime commands.
- Keep aircraft provider implementations in ThrowCore. ThrowUI uses the
  provider-neutral operation service and domain results.
- Keep one experience coordinator for all scenes. Only the active and
  prewarming experience runtimes may run at the same time.
- Exchange complete experience frames only while the projection is black.
  Never draw layers from two experiences together.
- Keep projected layer membership typed through ThrowCore. Erase it once in
  ThrowUI's `Projection/ProjectionFrame.swift` into closed presentation cases.
  Never accept erased marks back into a production case.
- Select exactly one aircraft source. Cancel and drain it before starting
  another; never combine or automatically fall back between providers.
- Keep source configuration and validation in one `AircraftSourceSelection`.
  Derive each paid provider's fixed credential ID from its source kind.
- Render Preview, full-screen fallback, and external displays with the same
  `ProjectionSurface`.
- Keep secrets in `AircraftCredentialStore` only. Never log a key, observer or
  Map-center coordinate, receiver URL, request URL, aircraft identity, or response body.
- Send production diagnostics through typed `ThrowLog` events. Do not import
  system logging or write raw diagnostic output.
- Keep post-launch operation failures in the typed owner ledger. Resolve only
  the owner whose operation succeeds.
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
scheme; do not add a separate snapshot scheme. Run
`./test --architecture-only` after changing a module boundary or composition
root.
