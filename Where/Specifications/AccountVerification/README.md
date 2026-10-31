# Account verification

Run `./tla-check AccountVerification CompatibilityVerification`.

This bounded companion to `CompatibilityVerification` checks account invalidation,
a suspended successful response, offline fallback, process restart, and recovery.
An account-change notification can mean the same account or a different account.
The local projection remains bound to account A. Account B cannot acquire it.

| Model | Production |
| --- | --- |
| `epoch`, `capturedEpoch` | Revocable account permit and compatibility check session |
| `invalidated` | `RecordingAccountBinding.invalidated` in the installation sidecar |
| `verified` | `RecordingAccountAccess` process-local identity verification |
| `access`, `grantedEpoch` | Current domain permit; retired permits stay revoked |
| `staleProjection` | Authority writes fenced at the store transaction boundary |
| `RestartProcess` | A new process requires identity verification before offline use |
| `VerifyCurrent` | Original account verified again before a fresh scope opens |

The current model checks that stale work cannot grant access or project authority,
that another account stays blocked, and that restart cannot restore invalidated trust.
Access means admission to a normal session. Previously admitted reads and external
displays can finish after lockout; `CompatibilityWrites` covers stale transactions.
Four negative controls remove each protection. Two reachability controls demonstrate
invalidation during a held response and successful recovery of the original account.

Bounds: two account identities, two sessions, one held response, one notification,
one restart, one offline retry, and one successful identity verification.
The old response is deliberately allowed to finish after cancellation.
The model assumes atomic sidecar replacement and the store's existing permit check
at transaction commit. Swift tests exercise those boundaries. It does not model
CloudKit delivery, server-side cancellation, account data migration, or liveness.
