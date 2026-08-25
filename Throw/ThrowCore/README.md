# ThrowCore

ThrowCore is Throw's UI-independent domain and services module. It normalizes
aircraft observations from the explicitly selected provider, maintains one
polling stream, predicts short motion windows, and projects semantic layer
marks into immutable frames for the UI.

## Install

Use the `ThrowCore` product from the repository's root Swift package. The
module imports Foundation, CoreLocation, Security, and PeriscopeCore; it does
not depend on SwiftUI, UIKit, WhereCore, or RegionKit.

## Public shape

The live catalog and public declarations in `Sources/` are authoritative. The
important boundaries are:

- validated geographic, viewport, calibration, source, layer, and frame
  values;
- `LayerCatalog.standard`, whose typed Flights descriptor constructs the live
  runtime and whose erased descriptor list is the catalog enumeration boundary;
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
state, and output demand. The session constructs the typed Flights runtime from
the same catalog that the controller presents. Expensive decode and projection
work stays off the main actor; late work is rejected by generation before it
can change live state.

## Privacy and limitations

Cloud requests use ephemeral sessions. Logging is typed and redacted: no
coordinates, coordinate-bearing URLs, receiver URLs, credentials, response
bodies, callsigns, or aircraft IDs. Aircraft data is incomplete and
non-safety-critical. True Sky treats provider altitudes as compatible
mean-sea-level approximations and is not an optical ceiling registration.

## Testing

`ThrowCoreTests` uses Swift Testing with injected clocks, HTTP, preferences,
credentials, and location. It never contacts a provider, GPS, UserDefaults, or
the Keychain. Run it with `./test ThrowCoreTests`.
