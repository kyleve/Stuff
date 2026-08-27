# ThrowCore – Module Shape

ThrowCore owns Throw's domain, projection, source, polling, persistence seams,
location, and scheduling; see [`README.md`](README.md). Read the root
[`AGENTS.md`](../../AGENTS.md) and group [`../AGENTS.md`](../AGENTS.md) first.

## Scope and dependencies

- Import Foundation, CoreLocation, Security, and PeriscopeCore only. Never
  import SwiftUI, UIKit, WhereCore, RegionKit, or LifecycleKit.
- Keep provider DTOs internal. Public source, layer, preference, and
  credential boundaries stay provider-neutral and typed.
- Keep GTFS schedule and realtime adapters behind `TransitScheduleSource` and
  `TransitObservationSource`. Do not expose generated protobuf types.
- Keep provider-specific setup and capability dispatch in
  `AircraftSourceService`. Presentation code uses its protocol only.
- Keep source factories at composition boundaries. A source never creates a
  global transport, store, poller, or credential.

## Invariants

- Normalize timestamps, altitude sentinels, missing position, identities, and
  padded callsigns at the DTO boundary. Never interpret missing wire values as
  zero.
- Require diagnostics for each snapshot construction.
- Preserve the counts through filters and wrappers. Aggregate them when snapshots merge.
- Log partial schema drift at warning level without provider record values.
- Represent each polling log event as one closed case with its required payload.
- Keep the flat version-three polling event wire vocabulary stable.
- Keep one structured poll task. Cancel and drain before replacement, and
  reject responses from an old generation.
- Publish polling as inactive or as active state with a coordinator-minted
  token. Mint a new token for each accepted replacement.
- Put active state in one coordinator-built envelope. Increase its revision
  within the token before each changed publication.
- Keep polling-clock sleep cancellation-only. A clock cannot add another
  polling failure state.
- Emit a readsb receiver-metadata cadence fallback as a separate warning event.
  Keep source activation informational.
- Carry polling cadence as a positive `AircraftPollingCadence`. Unwrap its
  `Duration` only at clock and date boundaries.
- Build FR24 bounds as a conservative spherical cap. Use all longitudes when
  the cap reaches a pole, and round transmitted edges outward.
- Never fall back between aircraft sources or merge their frames.
- Represent source setup with one `AircraftSourceSelection`. Never restore
  parallel selected and validated source properties.
- Derive provider credential IDs from the source kind. Never accept an
  arbitrary credential ID in a provider configuration.
- Build connection tests with `AircraftSourceValidationDraft`. Credential-free
  cases carry no replacement-credential field.
- Keep consecutive motion state inside the Flights runtime actor. Clear it when
  the selected source changes, and never persist it.
- Represent horizontal motion as `AircraftHorizontalMotion`. Available motion
  carries track, speed, source, and optional turn rate as one validated value.
- Pass `ResolvedAircraftObservation` values to frame builders. Never pass a
  separate observation collection and keyed motion lookup.
- Store only the RapidAPI key in device-only Keychain storage. Persist no live
  aircraft data or credential in preferences.
- Represent setup as `ThrowSetupState`. A configured setup carries its validated
  source, confirmed location, and projection mode as required values.
- Keep projection functions deterministic and independent of SwiftUI layout.
- Represent geodetic altitude as `GeodeticAltitude`. An available altitude
  carries its value and available quality together.
- Keep experience and layer catalogs compile-time and free of UI values. Add no
  runtime plugin or `AnyView` boundary.
- Keep shipped experience identities closed. Derive standard descriptors and
  presentation through exhaustive switches so a new case forces every owner to update.
- Keep the standard experience catalog authoritative. Pass
  `RunnableProjectionExperienceID` through playlist mutations. Keep
  `ProjectionExperienceID` at display and persistence boundaries.
- Construct semantic frames through typed layer and experience cases. Never pass
  parallel experience IDs, raw layer arrays, and modes across production boundaries.
- Keep layer IDs, mark element families, line styles, and payload shapes closed
  and typed through semantic and projected frames. Keep raw `LayerFrame`
  construction in DEBUG Testing SPI in `ProjectionModels.swift`.
- Derive an airport mark's identity and glyph from one descriptor. Never store
  a parallel airport ID beside that descriptor.
- Bind each semantic layer kind to its projected payload with
  `ProjectionMarkLayerKind` or `ProjectionLineLayerKind`.
- Derive renderer z-order from the closed `LayerID`. Never duplicate it in a
  catalog or presentation switch.
- Pass only `PreparedProjectionExperienceInput` to `ProjectionEngine`. Return a
  closed `ProjectedExperienceFrame` from projection.
- Project each present static-line source through a nonoptional preparation
  closure. Store its projected frame and source revision in one value.
- Create static-line frames with `ProjectionEngine.lineFrame`. Reject a prepared
  frame when its source revision or projection context does not match.
- Derive static-line render identity from its typed layer, source revision, and
  projection context. Never accept a caller-supplied revision ID.
- Never let a production engine API accept an arbitrary experience ID or
  erased layer array.
- Erase projected frames only in ThrowUI's `ProjectionFrame.swift`. Cache static
  lines by layer identity and semantic revision.
- Keep version-four preferences grouped by global, playlist, and experience
  ownership. Preserve exact version-one, version-two, and version-three
  migrations and existing Keychain IDs.
- Keep global and experience preferences as validated aggregate values. Use
  their replacement methods instead of mutable scalar mirrors.
- Represent temporary quiet wake durations as `TemporaryQuietWake`. Never pass
  a raw minute count across the session boundary.
- Treat MTA realtime partitions as independent failure domains. Do not remove a
  successful partition because another partition fails.
- Keep transit run identity scoped by agency, feed partition, service date, and
  stable run value. Do not use a route or trip ID as a vehicle identity.
- Keep scheduled and realtime transit data separate. Persist only the static
  schedule cache. Never persist a run, prediction, or estimated position.
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
- Pass attribution-load failure into the durable-logging starter. Emit its typed
  event after sink attachment, or before a store-open error returns.
- Route cold-launch and post-launch failures through the process-owned durable
  logging starter. Retain each typed event with its error attachment until attachment.
- Make the durable-logging starter the session-failure logger. Never inject a
  second logger beside it.
- Flush the existing sinks before the store handoff. Write each retained record
  to the store once, then release records that arrived during the handoff.
- Open one durable logging session through `PeriscopeThrowDurableLoggingStarter`.
  Keep OSLog active when the store cannot open or history pruning fails.

## Testing

Run `./test ThrowCoreTests`. Use injected deterministic dependencies and
memory-only stores; production network, GPS, UserDefaults, and Keychain are
forbidden in tests and previews.
