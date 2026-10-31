# Compatibility verification

Run `./tla-check CompatibilityVerification`.

Local history inspection can only block access. Full verification can restore it.
A local check does not join or satisfy the verification task.
A separate import can raise the required version during verification.

## Source correspondence

| Model | Production |
| --- | --- |
| `phase` | The shared `DataCompatibilityCoordinator.check` task and its suspended `evaluate` call |
| `remoteRequested`, `remoteCompleted` | Admission and completion of an explicit `recheck` request |
| `remoteRead`, `captured` | `RecordingDeviceCoordination.refreshForUse` and the evaluated decision |
| `LocalStep` | `recheckLocalHistory`, which preserves state when the local requirement is supported |
| `floor` | The locally observed requirement |
| `state` | The coordinator's published decision |

The model starts with blocked access and a supported local requirement.
Local inspection preserves that decision. Only completed, successful verification
can publish compatible access. An older completion cannot replace an observed
higher floor. Local history cannot clear a failed verification.

The current case checks safety and eventual completion of an admitted request.
Fairness applies only to reads and completions. It assumes that those operations
return, including with an error. It makes no network-delivery promise.
The authority layer's existing offline fallback remains outside this model.

Three negative controls omit verification, overwrite a higher floor, or grant
access from local history. A reachability control proves that local inspection
can run while verification waits. The former local/remote task modes and queued
remote handoff no longer exist in production or this model.

`DataCompatibilityCoordinatorTests` covers initial admission, waiting after a
sufficient synced floor, explicit recovery, concurrent callers, and local lockout
during a suspended remote read. It also covers offline fallback and account errors.

Bounds: one local inspection, one verification request, one import, and two versions.
The model omits local store-read failures.
The companion [`AccountVerification`](../AccountVerification/README.md) model covers
account invalidation, late responses, restart, and recovery of the original account.
