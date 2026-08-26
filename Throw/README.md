# Throw

Throw is an iPhone and iPad ceiling-projector app. It places nearby aircraft on
a geographic map or a directional sky dome. The device remains the controller,
and an attached display shows an opaque-black projection surface.
Aircraft data is ambient and incomplete; Throw is not a navigation or safety
tool.

## Modules

- [`ThrowCore`](ThrowCore) owns typed coordinates, projection math, ADS-B
  normalization and providers, polling, preferences, credentials, location,
  quiet scheduling, and the compile-time layer catalog.
- [`ThrowUI`](ThrowUI) owns the controller, onboarding and settings flows,
  calibration, and the one projection renderer shared by every output.
- [`Throw`](Throw) is the iOS composition root. It creates one runtime and
  hands its shared session to controller and external-display scenes.

The dependency direction is `ThrowCore` → `ThrowUI` → the `Throw` app. Throw
does not import WhereCore or RegionKit and does not use LifecycleKit.

## Build and run

Generate the workspace, then use the shared `Throw` scheme on an iOS 26 or
newer iPhone or iPad:

```bash
./ide --no-open
```

You can also build, install, and launch Throw on a connected device:

```bash
./ide --team-id <ABCDE12345> # one-time signing setup
./Throw/install
```

Run `./Throw/install --dry-run` to resolve the device without generating,
building, installing, or launching. Run `./Throw/install --help` for all
options.

The guaranteed physical-output path is a powered USB-C-to-HDMI connection.
AirPlay through Apple TV is supported by the system; if it mirrors instead of
creating a distinct external scene, use Throw's explicit full-screen output.
Preview runs the same projection renderer on the device.

## Aircraft sources

Setup requires an explicit, tested choice of `adsb.lol`, a user-owned local
`readsb` `aircraft.json`, the ADS-B Exchange Personal API through RapidAPI, or
the paid Flightradar24 API. Throw never mixes frames or silently falls back to
another source. API credentials belong to the user and remain in this device's
Keychain; the selected source and non-secret settings live in Throw preferences.

When labels are enabled, Throw optionally sends newly seen broadcast callsigns
to ADSBDB to resolve origin and destination. Aircraft and observer positions are
not included. Route results stay in a short-lived memory cache and do not delay
or affect the selected aircraft feed. Failed lookups pause for five minutes
before Throw tries the provider again.

When Flightradar24 is selected, origin and destination come from the same FR24
record as the aircraft position. Throw does not contact ADSBDB for that source.
FR24 bills the live full-position endpoint by returned aircraft, so credit use
depends on both polling cadence and local traffic density. The source settings
page reads the saved token's last 24 hours from FR24's usage report. Throw uses
the observed credits per request to estimate hourly and 30-day use. The report
can include requests that other clients make with the same token.

Throw keeps aircraft snapshots, routes, and motion history only in memory.
The app predicts from the last successful snapshot until the next poll.
A force quit removes that snapshot. The next launch requests current data.
At a five-minute cadence, the new result can differ from the previous display.

## Ambient flight activity

Throw estimates local arrivals and departures from route data and aircraft motion.
A local airport is within 50 NM of the observer.
Inbound and outbound cues stay dim until aircraft enter an approach or initial-climb stage.
These cues use small guide marks around each aircraft in Map and True Sky.

Map mode also shows the longest open runway for each relevant airport.
Confirmed airports show a code when labels are enabled.
Inferred airports stay graphical.
Throw bundles public-domain airport and runway geometry from OurAirports.

The activity stages are ambient estimates.
They do not identify literal touchdown or liftoff times.
This limitation is more visible when the selected aircraft source uses a slow polling interval.

The ADS-B Exchange path is for a personal beta using each user's own
personal/non-commercial subscription. Public distribution requires written
provider authorization, the applicable commercial terms, and a
provider-approved credential architecture that does not ship a shared secret
in the app. Those and the remaining physical release checks are tracked in
[`TODOs.md`](TODOs.md).

## Offline geography

Map mode draws a dim Geography layer behind aircraft. It includes generalized
coastlines, lakes, rivers, national boundaries, and regional boundaries. The
United States layer also includes state boundaries, county boundaries, and
primary roads.

The layer is on by default. You can turn it off or set its intensity from zero
through 20 percent. True Sky does not draw geography.

Map mode can use a center that differs from the observer location. Throw saves
one fixed center for each coarse observer region. A location refresh within
that region does not move the map. A small dim ring shows the observer location
when it is inside the visible Map. True Sky always uses the observer location.

Cloud aircraft sources receive a coarse version of the Map center and the query
radius. They do not receive the exact observer location when the centers differ.

Throw bundles Natural Earth Vector 1:10m data and selected 2025 U.S. Census
Bureau data. Map rendering does not request tiles or send a location to a map
provider. The generated archive contains no place names or road names.

The data is generalized and is not authoritative. Natural Earth boundaries use
the default de facto view. Census boundaries support statistical work and are
not legal land descriptions. See the [Natural Earth
terms](https://www.naturalearthdata.com/about/terms-of-use/) and the [2025
TIGER/Line documentation](https://www2.census.gov/geo/pdfs/maps-data/data/tiger/tgrshp2025/TGRSHP2025_TechDoc_Ch1.pdf).

## External scenes

iOS 26 discovers noninteractive external displays through the declared scene
role. On iOS 27, the controller also registers a retained
`UISceneAccessory.externalNonInteractive` adapter. The iOS 27 integration was
compiled against the installed beta SDK and must be revalidated against the
iOS 27 GM SDK before release. Focus, keystone, and optical registration remain
projector responsibilities.

See [`AGENTS.md`](AGENTS.md) for the feature's editing rules and each module's
README for its public API and limitations.
