# ThrowCore – Module Shape

ThrowCore owns Throw's domain, projection, source, polling, persistence seams,
location, and scheduling; see [`README.md`](README.md). Read the root
[`AGENTS.md`](../../AGENTS.md) and group [`../AGENTS.md`](../AGENTS.md) first.

## Scope and dependencies

- Import Foundation, CoreLocation, Security, and PeriscopeCore only. Never
  import SwiftUI, UIKit, WhereCore, RegionKit, or LifecycleKit.
- Keep provider DTOs internal. Public source, layer, preference, and
  credential boundaries stay provider-neutral and typed.
- Keep provider-specific setup and capability dispatch in
  `AircraftSourceService`. Presentation code uses its protocol only.
- Keep source factories at composition boundaries. A source never creates a
  global transport, store, poller, or credential.

## Invariants

- Normalize timestamps, altitude sentinels, missing position, identities, and
  padded callsigns at the DTO boundary. Never interpret missing wire values as
  zero.
- Keep one structured poll task. Cancel and drain before replacement, and
  reject responses from an old generation.
- Build FR24 bounds as a conservative spherical cap. Use all longitudes when
  the cap reaches a pole, and round transmitted edges outward.
- Never fall back between aircraft sources or merge their frames.
- Keep consecutive motion state inside the Flights runtime actor. Clear it when
  the selected source changes, and never persist it.
- Store only the RapidAPI key in device-only Keychain storage. Persist no live
  aircraft data or credential in preferences.
- Keep projection functions deterministic and independent of SwiftUI layout.
- Keep experience and layer catalogs compile-time and free of UI values. Add no
  runtime plugin or `AnyView` boundary.
- Construct semantic frames through typed layer and experience cases. Do not pass
  parallel experience IDs, raw layer arrays, and projection modes across production boundaries.
- Keep projected frames generic over ordered mark and line layers. Cache static
  lines by layer identity and semantic revision.
- Keep version-two preferences grouped by global, playlist, and experience
  ownership. Preserve exact version-one migration and existing Keychain IDs.
- Project Geography with the selected regional Map center and saved calibration.
  Never use Mercator placement or draw it in True Sky.
- Keep observer and Map-center semantics separate. True Sky and local activity
  use the observer. Map projection, filtering, and cloud queries use its center.
- Keep every derived `MapRegionID` inside its persisted band ranges. Treat
  positive 180° longitude as the negative-dateline band.
- Change the pinned source manifest, generator, and generated archive together.
  Keep expected counts scoped to emitted records, and keep the archive free of
  names and unused source attributes.
- Keep aircraft-family and airline-brand classification provider-neutral and
  deterministic. Use only bundled type characteristics, emitter category,
  explicit ICAO airline designators, and curated direct callsign prefixes;
  never add an online or per-tail lookup.
- Keep route enrichment optional, request-bounded, and off the aircraft rendering
  path. Never persist or log its callsigns, routes, or response body.
- Keep downloaded source archives outside the tracked tree. Require an exact
  digest before the generator reads an archive.
- Keep `ThrowLog` payloads redacted according to the group privacy invariant.

## Testing

Run `./test ThrowCoreTests`. Use injected deterministic dependencies and
memory-only stores; production network, GPS, UserDefaults, and Keychain are
forbidden in tests and previews.
