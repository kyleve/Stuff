# Compatibility verification

Run `./tla-check CompatibilityVerification`.

This model separates local history inspection from remote authority verification.
One local check and one remote request can overlap at the read and completion boundaries.
A separate import can raise the required version during either check.

## Source correspondence

| Model | Production |
| --- | --- |
| `mode`, `phase` | `DataCompatibilityCoordinator.check` and its suspended `evaluate` task |
| `remotePending` | A remote caller waiting for an existing local check to finish |
| `remoteRead` | `RecordingDeviceCoordination.refreshForUse` |
| `floor` | A requirement observed through `recheckLocalHistory` |
| `state` | The coordinator's published decision |

A remote request must perform remote verification before it completes.
A local task cannot satisfy that request.
A higher observed floor survives older completions.
Local history cannot clear a known verification failure.

The current case checks safety and eventual completion.
Fairness applies only to admitted reads, completions, and queued remote checks.
It assumes those operations return, including with an error.
It makes no network-delivery promise.

The three negative controls separately omit remote verification, overwrite a higher floor,
and clear a known failure through local history.
The reachability control demonstrates that a remote caller joins a local check.
The `local-satisfies-remote` control reproduces the reviewed coalescing defect.
The current case describes the corrected protocol and its companion Swift regression.

Bounds: one local check, one remote request, two versions, and one failed account verification.
CloudKit retry policy and storage decoding have separate Swift tests.

The companion [`AccountVerification`](../AccountVerification/README.md) model covers
account invalidation, late successful responses, restart, offline fallback, and
recovery of the original account. This model continues to isolate request coalescing
and the monotonic local compatibility floor.
