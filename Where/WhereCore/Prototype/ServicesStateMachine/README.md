# Services state machine prototype

Exploratory sketch of **WhereServices as composable state machines** — not wired
into production. Shows what a third architecture direction looks like: every
fragile protocol becomes an explicit `(State, Event) → (State, [Effect])`
reducer; a thin orchestrator merges slices; a runner executes effects against
the real collaborators.

## Layout

```
ServicesSnapshot          ← composite frozen state
ServicesEvent             ← external commands + effect completions
ServiceEffect             ← scheduled side effects
ServicesMachine           ← top-level reduce()
ServicesMachineReplay     ← scenario tracer for tests
Machines/
  TrackingMachine         ← TrackingReconciliation.tla
  PostWriteMachine        ← PostWriteReconcile.tla
  IngestorMachine         ← IngestorQuiesce.tla
  LaunchMachine           ← LaunchLifecycle.tla
  ResetMachine            ← WhereServices.reset() ordering
```

**Out of scope** (stay plain actors in this prototype): `ReportReader`,
`BackupCoordinator` export progress, `RecentActivitySummarizer`, evidence reads,
data-issue detection rules.

## How to read it

1. Open `ServicesSnapshot.swift` — the whole system's state at a glance.
2. Open `ServicesMachine.reduce` — one event enters, effects leave.
3. Pick a sub-machine (e.g. `TrackingMachine`) — maps 1:1 to an existing TLA
   spec README under `Where/Specifications/`.
4. Run `ServicesStateMachineTests` — replays the same scenarios the TLA configs
   name (enable/disable, post-write ordering, reset quiesce).

## Production mapping (if this were real)

| Prototype | Today |
| --- | --- |
| `ServicesMachine.reduce` | `WhereSession` + `DayJournal` + `WhereServices.init` closures |
| `ServiceEffect` cases | `await services.<actor>.…` |
| Effect completion events | async task resume / actor callback |
| `ServicesMachineReplay` | Swift Testing scenario tests + TLA model |

A production runner would live in WhereUI (session) and WhereCore (journal),
replacing ad-hoc `Task` loops incrementally — one protocol at a time.

## Related work

- TLA specs: `./tla-check` (8 specs on `cursor/tla-protocol-expansion`)
- Pure-core prototypes: #188 `TrackingReconcile`, #189 `PostWriteReconcilePlan`
- This branch stacks both ideas: **pure cores become sub-machine reducers** inside
  one composable snapshot.

## Status

Draft / look-only. Delete or promote individual machines after review — the
point is to *see* the shape, not migrate the app in one pass.
