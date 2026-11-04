# Compatibility activation

Question: can a lost server response or a concurrent refresh restore an older cached grant after a major activation starts?

This model represents `DataCompatibilityCoordinator.activateCurrentMajor` added above `0ded5000` in PR #476.
Run `./tla-check CompatibilityActivation` from the repository root.

| Model boundary | Production boundary |
| --- | --- |
| `RetireScope` | Install the activation token, revoke the old permit, and synchronously persist `verified: false`. Failure exits before the first server suspension. |
| `ConditionalServerSave` | Conditional server commit, independent of response delivery. |
| `ServerResponse` | Successful confirmation or a lost response. |
| `Begin`, `Receive` | Refresh request and completion. The activation token blocks new requests; superseded requests cannot grant access. |
| `AfterUncertainOutcome` | Failed offline refresh may use only a still-verified cache. |
| `VerifyAfterMutation` | Fresh verification restores access under the confirmed major. |

The bounds are one activation, one competing refresh, one offline attempt, and one recovery.
Majors are zero and one. Each label is an atomic boundary; the server save and response remain separate.
`TypeOK` covers every variable. `NoOldGrantAfterActivation` rejects stale grants during activation and after an uncertain commit.
`FailedInvalidationPreventsMutation` requires durable invalidation before any server write.

Verified for these model bounds and assumptions. All four cases meet their expected results.
The current case generates 121 states, with 48 distinct states and depth 9.
Removing the fence admits major zero during activation. Removing durable invalidation restores zero after a lost response.
The reachability control confirms that a fresh verification can recover at major one after that lost response.

The model assumes an atomic conditional server save and synchronous local cache persistence.
It is a safety model with no fairness or eventual-delivery claim. Stuttering is allowed.
It excludes repeated activations, real account services, payload decoding, and output publication.
`DataCompatibilityCoordinatorTests` separately controls overlapping activation lifetimes, stale automatic recovery, and cache-write failure.
`CloudKitDataCompatibilityTransportTests` covers concurrent server changes and lost creation responses.
The [verification model](../CompatibilityVerification/README.md) covers newness and independent metadata or record delivery.
