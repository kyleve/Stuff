# IntentServices handoff

Run `./tla-check IntentServicesHandoff`.

The model gives each consumer its own continuation, service epoch, and presentation epoch.
A compatibility block rejects parked consumers.
Already-resumed consumers retain their captured context until their next validation.
Recovery installs a new epoch and never revives an old permit.

## Source correspondence

| Model | Production |
| --- | --- |
| `availability`, `installed` | `IntentServices.availability` |
| `parked`, `resumed` | The waiter dictionary and checked continuations |
| `context`, `theme` | The atomic `IntentServices.Context` |
| `revoked` | Scope permits revoked before lifecycle teardown |
| `Use` | Access validation in `currentContext` and before the final intent result |

Safety checks cover one resume per parked consumer, matching context identities,
rejection of revoked results, and preservation of the compatibility block through `clear()`.
The liveness check assumes an already-resumed consumer eventually reaches its validation.
It does not assume that launch or CloudKit eventually succeeds.

Negative controls omit validation, permit self-creation, lose the block on clear,
or retain a resumed continuation in the waiter dictionary.
Reachability controls exercise two parked waiters and an old consumer after recovery.
Swift guards live in `IntentServicesTests` and `WhereIntentReaderTests`.

Bounds: two consumers, two installation epochs, and one compatibility block/recovery cycle.
Installation callbacks remain serialized by the launch runner.
This model does not authorize overlapping installs from independent launch runners.
An intent result already delivered to the OS cannot be recalled by this handoff.
