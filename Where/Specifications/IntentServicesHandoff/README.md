# IntentServices handoff

Run `./tla-check IntentServicesHandoff`.

The model gives each consumer its own continuation, service epoch, and presentation epoch.
A compatibility block rejects parked and new consumers. An admitted reader can
finish with its captured context after lockout or recovery. Writes use the
separate transaction boundary modeled by `CompatibilityWrites`.

| Model | Production |
| --- | --- |
| `availability`, `installed` | `IntentServices.availability` |
| `parked`, `resumed` | The waiter dictionary and checked continuations |
| `context`, `theme` | The atomic `IntentServices.Context` |
| `Use` | An admitted read finishes without another compatibility check |

Safety checks cover one resume per parked consumer, matching context identities,
and preservation of the compatibility block through `clear()`. The liveness
check assumes an admitted reader eventually finishes. It does not assume that
launch or CloudKit eventually succeeds.

Negative controls permit self-creation, lose the block on clear, or retain a
resumed continuation. Reachability controls exercise two parked waiters and an
old read after recovery. Swift guards live in `IntentServicesTests` and
`WhereIntentReaderTests`.

Bounds: two consumers, two installation epochs, and one block/recovery cycle.
The launch runner serializes installation callbacks. This model does not cover
overlapping installs from independent runners or recall results from the OS.
