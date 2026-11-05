# Multi-device decision merging

This concern checks the pure decision resolver from the
[multi-device design](../../MULTI_DEVICE_RECORDING.md#sync-and-concurrent-decisions).
Run it with `./tla-check MultiDeviceDecisions` from the repository root.
The [specification workflow](../README.md) defines translation and result policy.

## Bounds and assumptions

Two replicas receive four immutable operations over three elementary time periods.
Delivery permits every order, incomplete knowledge, and duplicate receipts.
Operations 1 and 2 disagree over one period. Operation 3 observes both and replaces only their overlap.
Operation 4 observes operation 3 and its transitive predecessors, but applies to a separate period.

Each receipt and local reassessment is one atomic step. The pure Swift resolver also reads one immutable input value.
The caller must supply a consistent store snapshot when persistence integration ships.
The model checks safety without delivery fairness. It makes no eventual-delivery or liveness claim.

The fixed graph assumes immutable, valid operation identities and a supported major contract.
The Swift resolver rejects identity collisions, unsupported majors, cycles, and empty scopes before assessment.
Identity allocation, crash recovery, guarded writes, and server acceptance are outside this initial model.
The durable-decision slice must refine those boundaries before activation.

## Source correspondence

| Model | Swift boundary |
| --- | --- |
| `delivered` | The lossless decision collection passed to `HistoryDecisionResolver.resolve` |
| `Scope` and `Times` | `HistoryDecision.periods` split at all intersecting half-open boundaries |
| `Ancestors` | Explicit predecessor closure computed by `CausalPeriodResolver.ancestors` |
| `Pending` | A nonempty missing-dependency set, abstracted to one unknown marker |
| `Maximal` | Active decisions with no active causal successor |
| `views` | Resolution abstraction: unknown for incomplete dependencies, otherwise the maximal decision identities |

The model abstracts away source-device names and version components. The Swift tests check compatible minor/patch versions and agreeing actions.
Its fixed graph knows all dependency edges. Missing dependency identity sets are abstracted to unknown status rather than compared exactly.
The implementation learns edges only from received records and retains missing identities explicitly.
`HistoryDecisionResolver` validates source-choice semantics, then delegates this topology to `CausalPeriodResolver`.
Ignore, place, and calendar controls use the same topology through separate typed identities and domain validation.
Their eligibility, calendar, and place meanings remain outside this model.

## Controls and regressions

`current` checks equal-knowledge convergence, missing dependencies, concurrent choices, and replacement scope.
The three broken variants discard missing knowledge, select an arbitrary concurrent winner, or replace outside the operation's scope.
Each variant must fail its named invariant.
The reachability case must reach a replica with a missing predecessor while another replica holds conflicting concurrent choices.

`HistoryDecisionResolverTests` covers replacement, reversal, partial overlap, missing dependencies, duplicate delivery, and all six three-operation orders.
It also covers agreement across compatible policies and rejection of invalid operations.
These checks do not establish production persistence or multi-device activation.
