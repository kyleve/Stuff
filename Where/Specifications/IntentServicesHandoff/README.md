# IntentServices handoff

The side-by-side Lean prototype in `WhereSpecifications/IntentServicesHandoff/Model.lean`
kernel-proves the current safety properties over every reachable state and
checks the broken trace. Run it with `./lean-check IntentServicesHandoff`; TLC
remains checked in while repository-wide fairness/deadlock parity is open.

Models [`IntentServices`](../../WhereIntents/Sources/IntentServices.swift): the App Intents
stack must never self-open a store; at most one installed stack is authoritative;
parked intents resume exactly once; `clear()` forces later callers to park until
the next `install(_:)`.

## Correspondence

| Model | Production |
| --- | --- |
| `installed` | `IntentServices.installed` |
| `waiterCount` | parked continuations in `current()` |
| `consumerPhase` | intent awaiting / holding / cancelled |
| `selfCreated` | forbidden fallback store open |

## Properties

- `NoSelfCreate` — no self-assembled stack
- `AtMostOneAuthoritative` — single install generation
- `WaiterExactlyOnce` — park has a matching resume or cancel
- `AfterClearMustPark` — holding requires an installed stack
- `NoMixedWorld` — consumers never run against a cleared install

## Result

**Verified for these model bounds and assumptions** on `Current.cfg`.
`Broken.cfg` (fallback `make()`) falsifies `NoSelfCreate`.

Swift guard: [`IntentServicesTests.clearWhileParkedResumesOnTheNextInstall`](../../WhereIntents/Tests/IntentServicesTests.swift).

Run: `./tla-check IntentServicesHandoff`
