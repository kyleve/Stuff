# Throw

Throw is an iPhone and iPad ceiling-projector app. It places nearby aircraft on
an observer-centred map or a directional sky dome, while the device remains the
controller and an attached display renders an opaque-black projection surface.
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
`readsb` `aircraft.json`, or the ADS-B Exchange Personal API through RapidAPI.
Throw never mixes frames or silently falls back to another source. RapidAPI
credentials belong to the user and remain in this device's Keychain; the
selected source and non-secret settings live in Throw preferences.

When labels are enabled, Throw optionally sends newly seen broadcast callsigns
to ADSBDB to resolve origin and destination. Aircraft and observer positions are
not included. Route results stay in a short-lived memory cache and do not delay
or affect the selected aircraft feed. Failed lookups pause for five minutes
before Throw tries the provider again.

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
