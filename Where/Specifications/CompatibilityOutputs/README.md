# Compatibility output lifetime

Run `./tla-check CompatibilityOutputs`.

This model checks retirement and replacement of `DataCompatibilityOutputs`.
Each service scope has a distinct epoch and one external publication.
The external adapter can finish after access revocation.
The old scope must drain and withdraw that publication before replacement starts.

## Source correspondence

| Model | Production |
| --- | --- |
| `revoked` | Irrevocable `DataAccessPermit` state |
| `lifetime` | The output actor's active, retiring, and retired states |
| `operation` | Admission, external adapter await, and final access validation |
| `Drain` | `retire()` waiting for the exclusive publication lane |
| `Recover` | Launch after the old scope's awaited retirement |
| `StaleRetire` | A late retirement or withdrawal call from the old scope |

Safety checks reject successful stale results and removal of replacement outputs.
After retirement completes, the old publication must be absent.
A bounded liveness check requires an admitted publication and retirement to finish.
Only those internal completions have fairness assumptions.

Negative controls remove the final validation, permit early replacement,
or allow a retired actor to withdraw again.
Reachability controls exercise a late external completion and a replacement publication.
Swift guards live in `DataCompatibilityOutputsTests` and `WhereCompatibilityLifecycleTests`.

Bounds: two scopes, one publication per scope, and one block/recovery cycle.
An OS adapter can briefly expose an in-flight publication before final validation withdraws it.
The model claims quiescent retirement, not instantaneous system-wide withdrawal.
Widget file atomicity and notification API failures have separate adapter tests.
