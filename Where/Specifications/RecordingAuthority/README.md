# Recording authority

Run `./tla-check RecordingAuthority`.

The model separates server authority, each device's cached authority, durable commands,
physical recording, requests in flight, and response delivery.
A crash clears process state but preserves the command and any request already sent.
The server can commit that request after the crash or a timeout.

## Source correspondence

| Model | Production |
| --- | --- |
| `revision`, `owner`, `request`, `floor` | `RecordingAuthority` and transport compare-and-save |
| `command`, `commands` | Persisted proposals with stable event identities |
| `inFlight`, `receipts`, `rejected` | Conditional commits, immutable receipts, and rejected stale proposals |
| `cachedOwner`, `cachedRevision`, `cachedTenure` | The verified local receipt projection |
| `Stop`, `running` | `DeviceRecordingController.approveHandoff` and physical ingestion |
| `Refresh` | Terminal-command reconciliation after remote verification |
| `removed` | Removal tombstones already delivered to the approving installation |
| `recovered` | Explicit replacement without the former phone's approval |

Normal transfers require a durable stop fence before commit.
A pending cancellation also retains the fence until the server confirms its outcome.
Fresh server history resolves completed or rejected commands without inventing a new event ID.
Known removed targets cannot receive an approved handoff.
An owner cannot remove the target of its pending request.
Only the current owner can raise the global version.

## Checks and controls

The current case checks normal recording exclusivity, known target eligibility,
owner-only upgrades, and eventual reconciliation of a committed command.
The repeated case reaches phone → replacement → phone with a new tenure.
The recovery case permits the documented overlap with an offline former owner.
Its other safety properties still apply.

Negative controls reproduce lost-response deadlock, approval of a removed target,
loss of the durable fence, a secondary upgrade, and premature release of a cancellation fence.
Reachability controls exercise lost-response reconciliation, reacquisition, and forced-recovery overlap.
The current cases describe the corrected protocol and the companion Swift regressions.

The cancellation counterexample has these steps:

1. Persist an approval and stop the old recorder.
2. Send the approval, then crash before its response.
3. Persist a cancellation while the original request remains in flight.
4. Let the original approval commit first.
5. Restart the old recorder from cached ownership after the cancellation removes its fence.
6. Start the new owner. Both devices now record.

## Bounds and assumptions

The model starts after the initial claim, with two registered installations and version 1.
`RecordingAuthorityTransportTests` separately cover competing initial claims.
Configurations bound commands, server revisions, crashes, and recovery explicitly.
The liveness case starts with a pending handoff and allows one command per device.
The repeated case allows two commands per device and omits failures to isolate tenure reuse.
The recovery case allows one forced replacement with reordered responses and one crash per device.

Fairness applies to local stop, send, and refresh operations.
A successful refresh is assumed eventually for the reconciliation property.
Server delivery and responses have no fairness guarantee.
This does not promise recovery while a device remains offline.

The removal check concerns tombstones already known to the approver.
It does not establish atomic ordering between CloudKit authority and an undelivered SwiftData removal.
The model also excludes authentication, storage failure, sample timestamps, and cutoff filtering.
`RecordingRecoveryExclusionTests` and backup tests cover lossless history and cutoff projection.
These bounded results do not prove the Swift implementation or CloudKit itself correct.
