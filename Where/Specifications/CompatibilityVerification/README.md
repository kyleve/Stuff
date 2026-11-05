# Compatibility verification

Question: can delayed verification or record delivery lower known requirements or restore access through a retired account binding?

This model represents the compatibility protocol added above `0ded5000` in PR #476.
It follows [the primary contract](../../MULTI_DEVICE_RECORDING.md#compatibility).
Run `./tla-check CompatibilityVerification` from the repository root.

## Source correspondence

| Model state or action | Production boundary |
| --- | --- |
| `server`, `serverHigh`, `GuardedInitialization` | `CloudKitDataCompatibilityTransport.initialize`; database creation uses a conditional record save. A competing creator wins. |
| `localFloor` | `SwiftDataStore.raiseRequiredDataMajor`, inside a local transaction. |
| `known`, `durable`, `ReceiveVerification` | `DataCompatibilityCoordinator.rememberSharedRequirement`; observation is persisted before checking the request token. |
| `epoch`, `requestEpoch`, `grantEpoch` | Coordinator attempt identity and account invalidation. |
| `response`, `StartVerification`, `FailedRefresh` | Suspended verification, late completion, and failed refresh. Failure does not erase valid same-binding access. |
| `verified`, `access` | Same-process verification proof and a fresh `DataCompatibilityAccess`. |
| `cacheVerified`, `cachedEpoch`, `identifiedEpoch` | Durable cache admission, its binding, and separately established current identity. |
| `lostMajor` | Ghost state retaining a requirement whose cache write failed; it detects an obsolete grant after relaunch. |
| `EstablishIdentity`, `UseOfflineCache` | Cold offline admission requires current identity and a valid matching durable grant. |
| `records`, `ReceiveRecordHeader` | `VersionedHistoryRecord.Header`, checked before payload decoding. |
| `ConfirmMajor`, `AuthorRecord` | Server confirmation precedes authoring the higher-major envelope. |
| `Relaunch` | Reconstruct knowledge from durable cache; establish current identity before granting access. |

Each label marks one atomic model action. Network reads, conditional creation, completion, and account invalidation are separate actions.
The in-process cache write is synchronous. `FailHighWrite` exercises a failed save after observing major one.
Each online read invalidates the durable grant first. A completed transient failure can restore the unchanged live proof.
A crash during a pending check leaves durable admission invalid; cold offline startup waits for fresh verification.
The `client` variable selects an atomic client action. It carries no production authority.
The two clients support majors through zero and one respectively. Each can cross one binding epoch.
Shared and local datasets, with and without legacy data, use separate configurations.

`TypeOK` covers every variable. Safety properties check monotonic requirements, durable knowledge, current-binding grants, and admission before decoding.
Record-first and stale-completion controls establish reachability.
Negative controls inspect the same properties after removing conditional initialization, token validation, durable observation, or header admission.
Their traces show a lower creator overwriting an established major, an old epoch granting access, forgotten higher knowledge, and unsupported payload interpretation.

## Results and limits

Verified for these model bounds and assumptions with the tools pinned by `./tla-check`.
All twelve manifest cases meet their expected results.

| Passing configuration | Generated / distinct states | Depth |
| --- | ---: | ---: |
| Shared, new | 1,711,005 / 468,620 | 36 |
| Shared, legacy | 1,680,551 / 463,360 | 36 |
| Local, new | 490,891 / 130,060 | 36 |
| Local, legacy | 803,805 / 215,300 | 38 |
| Failed higher-floor write | 3,249,383 / 919,120 | 40 |

This is a safety model. It makes no fairness or eventual-network-delivery claim.
The stuttering environment prevents intentional unavailable states from appearing as deadlocks.
The shared zone inventory establishes newness under the rollout assumption that pre-foundation writers are retired before incompatible activation.
The model assumes atomic conditional server storage; it does not implement CloudKit, its network, or its account service.
Eligibility, payload meaning, multiple outstanding requests on one client, and output withdrawal are outside this model.
Swift regressions cover overlapping requests and prevent one completion from restoring a durable grant while another response remains pending.
The [activation model](../CompatibilityActivation/README.md) covers uncertain saves; the [write model](../CompatibilityWrites/README.md) covers physical local commits.

`DataCompatibilityCoordinatorTests` covers stale responses, relaunch, empty stores, account changes, and supported imports.
`CloudKitDataCompatibilityTransportTests` runs production transport logic through a conditional database fixture.
`SwiftDataStoreCompatibilityTests` checks admission against real SwiftData transactions, including a record received before metadata.
`VersionedLocationSample` puts major-one GPS and its version in that same atomic envelope.
`SwiftDataStoreLocationSamplesTests.observationBeforeSharedFloorBlocksAFoundationReader` checks this delivery order with a real observation.
The model's record-header abstraction covers this storage boundary; it does not verify location payloads or calendar assignments.
The fixture does not claim live CloudKit validation. Recheck source correspondence whenever these boundaries change.
