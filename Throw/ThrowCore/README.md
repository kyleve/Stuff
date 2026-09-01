# ThrowCore

ThrowCore is Throw's UI-independent domain and services module. It normalizes
aircraft observations from the explicitly selected provider, maintains one
polling stream, predicts motion, and projects semantic experience layers into
immutable frames for the UI.

## Install

Use the `ThrowCore` product from the repository's root Swift package. The
module imports Foundation, CoreLocation, Security, and PeriscopeCore; it does
not depend on SwiftUI, UIKit, WhereCore, or RegionKit.

## Public shape

The live catalog and public declarations in `Sources/` are authoritative. The
important boundaries are:

- validated geographic, viewport, calibration, source, experience, playlist,
  layer, and frame values;
- fixed Map centers that are stored by coarse observer region;
- `ProjectionExperienceCatalog.standard` and `LayerCatalog.standard`, which
  define fixed View and layer membership at compile time;
- `AircraftObservationSource`, the provider-neutral one-shot feed contract;
- `AircraftSourceOperationServing`, the provider-neutral setup and usage
  boundary used by presentation code;
- HTTP, preference, credential, location, and clock protocols, with live and
  deterministic in-memory implementations;
- the polling coordinator, prediction, quiet scheduler, and pure projection
  engine.

Coarse Map regions use one-degree bands. The north pole uses the final northern
band, and positive 180° longitude shares the negative-dateline band.

`adsb.lol`, local `readsb`, and ADS-B Exchange RapidAPI use separate request
and envelope adapters around the reusable ADS-B Exchange-v2 aircraft decoder.
Flightradar24 has its own live-position decoder. Both decoders retain usable
rows and report aggregate malformed and missing-position counts. The polling
log records these counts at warning level. Every snapshot construction supplies
these diagnostics. Filters and response wrappers preserve them.
Each FR24 snapshot carries a completed route result for each aircraft. The result
is unavailable when the same record has no usable route. FR24 zero-altitude positions normalize as
ground because its position schema has no separate airborne-state field. The
FR24 adapter also reads the account's 24-hour usage report. Its estimator uses
the reported credits per request, the selected cadence, quiet hours, and the
current region's request multiplicity.
`readsb` receiver metadata selects its cadence. If metadata fails, Throw uses
one second and emits a separate warning event. Source activation remains
informational.
Aircraft polling log events use case-specific payloads. Their flat version-three
wire keys and kind values stay stable for existing Periscope records.
Source configuration carries no credential value or credential ID. Each paid
provider selects its fixed Keychain slot through `AircraftCredentialID`.
`AircraftSourceValidationDraft` is the temporary setup boundary. Only its paid
provider cases can carry a replacement credential and derive a Keychain ID.
An FR24 bounds query that crosses the antimeridian uses two valid hemisphere
requests. Both must succeed before Throw publishes the merged snapshot.
Duplicate aircraft keep the freshest observation and its matching route.
FR24 bounds use a spherical cap that matches Throw's local distance model.
A cap that reaches either pole requests all longitudes. Other bounds round
outward so provider coordinates on the local filter boundary are not omitted.

## Composition

`ThrowSession+Composition.swift` creates the live stores, source graph, poller,
and session once. ThrowUI's shared session drives the poller according to
foreground, quiet, and output demand. Version-two preferences separate global,
playlist, and Air & Space state. The codec migrates version-one data under the
existing storage key. Validated preference aggregates stay intact through the
session boundary. Raw values exist only at editing and codec boundaries.
Keychain credential IDs do not change.

Setup is one typed lifecycle value. Its configured case requires a validated
source, confirmed location, and projection mode. The codec reconstructs this
state from the stable version-one and version-two fields.

The process starts one Periscope store and attaches it to Throw's typed log.
The session logger sends failures to OSLog while this store opens. It also
retains each exact typed record and its error attachment. The handoff writes
these records to the store once before new session records use the attached sink.
The store keeps at most 100 days and 50,000 events. A store error leaves OSLog
active and produces a typed error event. A history-prune error does not make
an attached store unavailable.

Composition gives software-attribution failure to the durable logging starter.
The starter records the error after the store attaches. Existing sinks receive
the event if the store cannot open.

`AircraftSourceSelection` keeps unconfigured, awaiting-validation, and
configured source state in one value. A configured source cannot disagree with
a separate validation flag.
`TemporaryQuietWake` closes the supported 15-minute, 30-minute, and 60-minute
wake choices. Session intents do not accept other minute values.

`LayerID`, `LayerMarkID`, and `ProjectionLineStyleID` are closed typed values.
`GeodeticAltitude` stores altitude availability, value, and quality in one
state. An unavailable altitude cannot carry a quality.
`ProjectionLayerFrame` fixes each semantic layer identity and payload shape in
its generic type. A mark layer cannot receive line content, and a line layer
cannot receive marks. Raw `LayerFrame` construction stays at the Core erasure
boundary.
`ProjectionExperienceFrame` then accepts only the typed layers for its experience.
`ProjectionExperienceInput` also pairs each experience with its supported projection modes.
Transit can accept only a Map viewport. Geography visibility belongs to Map
inputs, so it cannot be requested in True Sky.
`ProjectionExperienceID` is a closed raw-value enum. The standard catalog derives
its descriptors from those cases, so a new shipped experience requires exhaustive work.

`ProjectionMarkLayerKind` and `ProjectionLineLayerKind` bind each semantic
payload to its projected payload. `ProjectedLayerFrame` keeps that binding
through `ProjectionEngine`. Its mark initializer checks the erased
`LayerMarkID` tag before it stores a mark.
`ProjectedExperienceFrame` fixes each experience's projected layers and modes.
Air & Space True Sky cannot carry Geography. Transit cannot carry Air & Space
layers or a True Sky mode. Map output cannot carry the True-Sky-only Stars
layer. Layer identity also owns the fixed renderer z-order.

The worker converts `ProjectionExperienceInput` into one closed
`PreparedProjectionExperienceInput` after it projects static lines. The engine
accepts that value and returns the matching `ProjectedExperienceFrame`.
ThrowUI erases the closed output once in
`ProjectionFrame.swift`, at the renderer boundary.

Line styles are typed, so Geography and future transit routes use one
projection path. `ProjectionEngine.lineFrame` records the semantic source
revision and full projection context in each static-line frame. The engine
rejects a prepared frame from another source revision or projection context.
It derives the render identity from this provenance. Callers cannot supply an
arbitrary revision ID or replace the projected payload.
The worker caches static lines by layer, revision, Map center, viewport,
calibration, and geometry.
It does not rebuild them at the 30 Hz mark rate. Expensive work stays off the
main actor. Generation checks reject late work.
Position prediction continues until a later successful poll replaces the
snapshot. A retryable poll failure starts a 15-second grace period and a
15-second fade.

The Flights runtime compares consecutive positions for each aircraft.
Valid provider track and speed remain authoritative.
Observed positions supply motion when provider values are missing or clearly inconsistent.
Recent provider tracks can supply a bounded turn rate.
Horizontal motion is one typed value: an available value always has track,
speed, and source, while orientation-only observations remain unavailable for
translation. Turn rate exists only inside available horizontal motion.
The motion estimator pairs each observation with its resolved motion before it
calls the Flights frame builder. The builder cannot receive missing motion.
Throw uses that turn rate for the first 12 seconds of a prediction.
The runtime removes this history when the source changes or the app runtime ends.

`Tools/generate-geography.rb` creates the bundled archive from pinned Natural
Earth Vector 1:10m and U.S. Census Bureau inputs. A source manifest records each
official URL, release, file member, and SHA-256 digest.

The generator filters features, removes names, splits antimeridian paths, and
simplifies linework. It then quantizes coordinates and assigns wide, standard,
or local visibility. The committed archive lets every app build stay offline.
Raw source archives stay outside the tracked tree.

`Tools/generate-aircraft-types.rb` creates the bundled ICAO type lookup from a
pinned Mictronics aircraft-database archive. Throw keeps only the designator,
airframe and engine description, and wake category. The visual classifier uses
that lookup with the provider's emitter category to select one of six stable
silhouette families. A small curated callsign-prefix table can add a carrier
identity. It does not perform online, route, registration, or operator-name
lookups for aircraft classification. Separately, the route resolver sends up to
12 newly seen callsigns per pass to ADSBDB, with at most four concurrent
requests. It caches successful routes for six hours and unknown routes for one
hour. A provider failure pauses lookups for five minutes. Cancellation does not
start this cooldown. Aircraft rendering
does not wait for this optional enrichment. The resolver is not used for
Flightradar24 snapshots because FR24 supplies position and route fields in one
response.

`Tools/generate-airports.rb` creates the bundled airport catalog from a pinned
OurAirports revision. The manifest fixes both source-file digests and the
generated-resource digest. Its counts describe the airports and runways that
the archive emits, not all valid rows in the source files. The catalog includes
active coded airports, elevations, code aliases, and open runway endpoints.

The activity classifier treats an airport within 50 NM of the observer as
local. Route data can confirm an arrival or departure estimate. Strict motion,
altitude, distance, and runway-alignment rules can infer an estimate without a
route. Ground aircraft and observations without altitude or vertical rate do
not receive inferred activity.

## Privacy and limitations

Cloud requests use ephemeral sessions. Logging is typed and redacted: no
coordinates, coordinate-bearing URLs, receiver URLs, credentials, response
bodies, callsigns, or aircraft IDs. Aircraft data is incomplete and
non-safety-critical. True Sky treats provider altitudes as compatible
mean-sea-level approximations and is not an optical ceiling registration.
The offline map sends no request. Its generalized boundaries are not
authoritative. Natural Earth uses its default de facto view. Census boundaries
support statistical work and are not legal land descriptions.
Cloud aircraft sources receive the coarse query center. In Map mode, this value
can differ from the observer location. True Sky always uses the observer location.
Aircraft classifications and carrier identities are not persisted or logged.
Aircraft snapshots, routes, and motion history are not persisted.
Projection logs contain only aggregate cadence, age, motion, correction, and snapshot-overlap values.
Durable session logs contain build and device metadata, readiness, failure,
and aggregate retention counts.
Route enrichment sends broadcast callsigns to ADSBDB. It never sends aircraft
or observer positions, persists route history, or logs route request or
response values.

## Testing

`ThrowCoreTests` uses Swift Testing with injected clocks, HTTP, preferences,
credentials, and location. It never contacts a provider, GPS, UserDefaults, or
the Keychain. Run it with `./test ThrowCoreTests`.
