# ThrowCore

ThrowCore is Throw's UI-independent domain and services module. It normalizes
aircraft observations from the explicitly selected provider, maintains one
polling stream, predicts short motion windows, and projects semantic layer
marks and bundled geographic lines into immutable frames for the UI.

## Install

Use the `ThrowCore` product from the repository's root Swift package. The
module imports Foundation, CoreLocation, Security, and PeriscopeCore; it does
not depend on SwiftUI, UIKit, WhereCore, or RegionKit.

## Public shape

The live catalog and public declarations in `Sources/` are authoritative. The
important boundaries are:

- validated geographic, viewport, calibration, source, layer, and frame
  values;
- `LayerCatalog.standard`, whose typed Flights and Geography descriptors
  construct live runtimes and whose erased list is the catalog boundary;
- `AircraftObservationSource`, the provider-neutral one-shot feed contract;
- HTTP, preference, credential, location, and clock protocols, with live and
  deterministic in-memory implementations;
- the polling coordinator, prediction, quiet scheduler, and pure projection
  engine.

`adsb.lol`, local `readsb`, and ADS-B Exchange RapidAPI use separate request
and envelope adapters around the reusable ADS-B Exchange-v2 aircraft decoder.
Flightradar24 has its own live-position decoder. Each FR24 snapshot carries a
completed route result for each aircraft. The result is unavailable when the
same record has no usable route. FR24 zero-altitude positions normalize as
ground because its position schema has no separate airborne-state field. The
FR24 adapter also reads the account's 24-hour usage report. Its estimator uses
the reported credits per request, the selected cadence, and quiet hours.
Configuration carries a typed credential reference, never the credential itself.

## Composition

The app creates live preference and credential stores once. ThrowUI's shared
session drives the polling coordinator according to foreground state, quiet
state, and output demand. The session constructs typed runtimes from the same
catalog that the controller presents. The worker decodes bundled geography once
and caches projected lines by location, viewport, and calibration. It does not
rebuild static lines at the 30 Hz aircraft frame rate. Expensive decode and
projection work stays off the main actor. Generation checks reject late work.
Position prediction stops after 15 seconds, but a successful snapshot stays
visible until a later successful poll replaces it. A retryable poll failure
starts a 15-second grace period and a 15-second fade.

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
hour. A provider failure pauses lookups for five minutes. Aircraft rendering
does not wait for this optional enrichment. The resolver is not used for
Flightradar24 snapshots because FR24 supplies position and route fields in one
response.

`Tools/generate-airports.rb` creates the bundled airport catalog from a pinned
OurAirports revision. The manifest fixes both source-file digests and the
generated-resource digest. The catalog includes active coded airports,
elevations, code aliases, and open runway endpoints.

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
Aircraft classifications and carrier identities are not persisted or logged.
Route enrichment sends broadcast callsigns to ADSBDB. It never sends aircraft
or observer positions, persists route history, or logs route request or
response values.

## Testing

`ThrowCoreTests` uses Swift Testing with injected clocks, HTTP, preferences,
credentials, and location. It never contacts a provider, GPS, UserDefaults, or
the Keychain. Run it with `./test ThrowCoreTests`.
