# Scope exclusivity

Run `./tla-check ScopeExclusivity`.

The process bootstrap owns one real store across normal scope replacement.
Compatibility and onboarding gate domain scopes, not the bootstrap store.
Each new scope receives a fresh write permit.
Revocation remains permanent for transactions that retain an older scope.

## Source correspondence

| Model | Production |
| --- | --- |
| `realContainersAlive` | The retained store in `WhereBootstrap` |
| `activeScopes` | `WhereModel.activeScope` |
| `verified`, `onboardingGate` | Compatibility and recording/onboarding launch gates |
| `permits`, `revoked` | `DataCompatibilityCoordinator.openDomainStore` and `DataAccessPermit` |
| `suspended`, `completed` | Transactions that retain a scope across an await |
| `Flyover` | A separate in-memory sibling that never activates the real scope |

The model checks one container, one active scope, gate ordering, and permanent revocation.
It replaces the obsolete assumptions that onboarding precedes store opening and logout closes the store.
Negative controls open a duplicate container, revive an old permit, or skip the gates.
Reachability controls exercise retained bootstrap storage and a second domain scope.

Bounds: one process, two domain scopes, one compatibility block, and one retained transaction per scope.
This is a safety model without a delivery or launch-completion guarantee.
`CompatibilityWrites` checks that revoked scopes cannot commit after recovery.
External publications can finish after teardown.
`LogRouting` separately checks sink ownership.
Swift guards live in `WhereCompatibilityLifecycleTests`, `WhereResetTests`, and `DataCompatibilityCoordinatorTests`.
