# Throw protocol specifications

These bounded models check narrow concurrency claims in Throw. Each concern contains an editable
model in TLA+ or PlusCal. It also contains TLC configurations, a manifest, and a source map.

| Concern | Model source | Claim |
| --- | --- | --- |
| [Preference transactions](PreferenceTransactions/README.md) | PlusCal | Preference mutations publish only durable state and cannot revive an obsolete observer context. |
| [Projection activation](ProjectionActivation/README.md) | PlusCal | Projection leases, permits, and physical polling stay aligned during activation races. |
| [Projection context transition](ProjectionContextTransition/README.md) | TLA+ | A transition cannot publish an invalid context, mismatched visible pair, or competing writer. |
| [Background preference persistence](BackgroundPreferencePersistence/README.md) | TLA+ | A background flush closes producer admission and releases each retained UIKit lease safely. |
| [Polling publication](PollingPublication/README.md) | PlusCal | Token-bound polling updates remain ordered during replacement, recovery, frame construction, and deactivation. |

List all concerns from the repository root:

```sh
./tla-check --list
```

Run one listed concern. For example:

```sh
./tla-check PreferenceTransactions
```

Use [`Where/Specifications/README.md`](../../Where/Specifications/README.md) for the shared
authoring and checker rules.
