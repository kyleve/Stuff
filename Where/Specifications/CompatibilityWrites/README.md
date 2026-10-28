# Compatibility writes

Run `./tla-check CompatibilityWrites`.

This model covers a transaction held across session lockout and recovery.
Lockout revokes the old scope's write permit. Recovery creates a new scope.
The old transaction checks its permit before save. A retained old caller cannot
start another transaction after recovery.

`OldTransaction` corresponds to `CompatibilityScopedStore.perform` and the
pre-save check in `SwiftDataStore`. `Lockout` corresponds to
`DataCompatibilityCoordinator.revokeAccess`. `FreshScope` corresponds to
`openDomainStore`.

The current case checks that old work cannot commit after revocation. Two
negative controls remove the commit check or reuse the revoked permit. The
reachability case proves that a new scope can commit after the old work finishes.

Bounds: one old transaction, one lockout, one recovery, and one late old caller.
The model assumes an atomic permission check and local commit boundary. It does
not model CloudKit delivery or an already submitted server write. Ordinary reads
and external displays can finish after lockout and are outside this contract.
Swift tests hold a transaction at suspension, revoke its permit, then release it.
