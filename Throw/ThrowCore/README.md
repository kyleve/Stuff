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
Configuration carries a typed credential reference, never the credential
itself.

## Composition

The app creates live preference and credential stores once. ThrowUI's shared
session drives the polling coordinator according to foreground state, quiet
state, and output demand. The session constructs typed runtimes from the same
catalog that the controller presents. The worker decodes bundled geography once
and caches projected lines by location, viewport, and calibration. It does not
rebuild static lines at the 30 Hz aircraft frame rate. Expensive decode and
projection work stays off the main actor. Generation checks reject late work.

`Tools/generate-geography.rb` creates the bundled archive from the pinned
Natural Earth Vector 1:50m inputs. The archive contains quantized line geometry
and display ranks. It contains no place names. The source README records the
release, hashes, terms, and generation command.

## Privacy and limitations

Cloud requests use ephemeral sessions. Logging is typed and redacted: no
coordinates, coordinate-bearing URLs, receiver URLs, credentials, response
bodies, callsigns, or aircraft IDs. Aircraft data is incomplete and
non-safety-critical. True Sky treats provider altitudes as compatible
mean-sea-level approximations and is not an optical ceiling registration.
The offline map sends no request. Its generalized boundaries are not
authoritative and use Natural Earth's default de facto view.

## Testing

`ThrowCoreTests` uses Swift Testing with injected clocks, HTTP, preferences,
credentials, and location. It never contacts a provider, GPS, UserDefaults, or
the Keychain. Run it with `./test ThrowCoreTests`.
