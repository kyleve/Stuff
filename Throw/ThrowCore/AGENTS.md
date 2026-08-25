# ThrowCore – Module Shape

ThrowCore owns Throw's domain, projection, source, polling, persistence seams,
location, and scheduling; see [`README.md`](README.md). Read the root
[`AGENTS.md`](../../AGENTS.md) and group [`../AGENTS.md`](../AGENTS.md) first.

## Scope and dependencies

- Import Foundation, CoreLocation, Security, and PeriscopeCore only. Never
  import SwiftUI, UIKit, WhereCore, RegionKit, or LifecycleKit.
- Keep provider DTOs internal. Public source, layer, preference, and
  credential boundaries stay provider-neutral and typed.
- Keep source factories at composition boundaries. A source never creates a
  global transport, store, poller, or credential.

## Invariants

- Normalize timestamps, altitude sentinels, missing position, identities, and
  padded callsigns at the DTO boundary. Never interpret missing wire values as
  zero.
- Keep one structured poll task. Cancel and drain before replacement, and
  reject responses from an old generation.
- Never fall back between aircraft sources or merge their frames.
- Store only the RapidAPI key in device-only Keychain storage. Persist no live
  aircraft data or credential in preferences.
- Keep projection functions deterministic and independent of SwiftUI layout.
- Project Geography with the observer-centred Map math and saved calibration.
  Never use Mercator placement or draw it in True Sky.
- Change the pinned source manifest, generator, and generated archive together.
  Keep the archive free of names and unused source attributes.
- Keep downloaded source archives outside the tracked tree. Require an exact
  digest before the generator reads an archive.
- Keep `ThrowLog` payloads redacted according to the group privacy invariant.

## Testing

Run `./test ThrowCoreTests`. Use injected deterministic dependencies and
memory-only stores; production network, GPS, UserDefaults, and Keychain are
forbidden in tests and previews.
