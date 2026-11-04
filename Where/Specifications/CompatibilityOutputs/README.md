# Compatibility output withdrawal

Can an old asynchronous publication restore history after its scope has withdrawn output?
Can an old withdrawal erase replacement output?

This model describes `DataCompatibilityOutputQueue` and `DataCompatibilityOutputs` in the same revision.
It checks the output queue contract. Production lifecycle wiring must await retirement before replacement services publish.

| Model state or action | Source boundary |
| --- | --- |
| `revoked`, `Revoke` | `DataCompatibilityAccess.revoke()` closes the permit. |
| `queueClosed`, `CloseQueue` | `retire(withdraw:)` replaces active queue state with its retained withdrawal task. |
| `queued`, `Enqueue` | `publish` appends an owned task while the queue remains active. |
| `BeginSystemCall` | The task validates access after awaiting its predecessor. |
| `SystemAccepts` | An asynchronous notification operation completes, possibly after revocation. |
| `completed`, `Finish` | The publication task completes. Retirement can finish awaiting it. |
| `Drain` | Withdrawal awaits the last submitted task. |
| `output`, `Withdraw` | Owned notifications and widget history are removed. |
| `WaitForRetirement`, `Publish` | Replacement services wait for the previous scope's withdrawal. |

The model bounds one old publication, one retirement, and one replacement publication.
The four output families use the same queue; their individual system calls are abstracted as one call.
Caller cancellation does not abandon the queue-owned task. It therefore changes no model state.
Repeated retirement awaits the same task. It does not submit another withdrawal.

`TypeOK` checks all state domains. `NoObsoleteOutput` forbids old output after withdrawal.
`ReplacementSurvives` forbids later output changes after replacement publication.
The recovery control demonstrates that replacement publication is reachable.
No fairness or eventual-delivery guarantee is assumed. A stuttering environment can leave any system call pending indefinitely.

The model assumes the system honors completed removal calls and admits replacement work only after retirement.
It does not model notification permission errors, file I/O failures, WidgetKit refresh latency, or startup cleanup from another process.
The synchronous widget file write has an additional permit lock in `WidgetCenterTimelineRefresher`.
That lock is outside this model, which deliberately allows an already-submitted system call to finish after revocation.

Run `./tla-check CompatibilityOutputs` from the repository root.
All four cases met their expected results with the repository's pinned TLC and Java tools:

| Case | Result | Generated / distinct | Depth |
| --- | --- | ---: | ---: |
| `current` | Pass | 78 / 33 | 10 |
| `no-drain` | Expected `NoObsoleteOutput` failure | 88 / 38 | 8 |
| `accept-retired` | Expected `NoObsoleteOutput` failure | 62 / 28 | 8 |
| `recovery` | Expected `RecoveryNotReached` failure | 61 / 28 | 7 |

The no-drain trace submits old work, withdraws, then accepts that old work.
The accept-retired trace admits a new submission after queue closure, then publishes it after withdrawal.
These controls distinguish the ordering requirement from access validation at submission.

Swift coverage:

- `DataCompatibilityOutputQueueTests` holds a submitted operation, cancels its caller, and checks terminal withdrawal order.
- `DataCompatibilityOutputsTests` holds the production reminder scheduler at its injected system adapter.
  It checks pending and delivered history removal, badge clearing, widget withdrawal, and preservation of an independent update alert.
  A fresh scope publishes after retirement; repeated old retirement cannot erase it.
- `WidgetSnapshotStoreTests` checks actual temporary-file withdrawal.

These results establish bounded protocol behavior and deterministic application tests. They do not establish live CloudKit or OS delivery behavior.
