# PortholeLifecycle – Module Shape

PortholeLifecycle is the `lifecycle` Porthole connector: a `launch-state` data
source over a LifecycleKit `LifecycleRunner`. See [`README.md`](README.md).

This file complements the root [`AGENTS.md`](../../../AGENTS.md) — read it first.

## Scope & dependencies

- Depends on **PortholeKit** + **LifecycleKit** only. A separate module (not part
  of PortholeKit) because the runtime must not depend on LifecycleKit.
- **Inject the app's `LifecycleRunner`; never create one** (create-once/inject-down).

## Invariants

- **Reads the runner on the main actor** (it's `@MainActor`), snapshotting into a
  Sendable row. It surfaces exactly what the runner publishes — `phase`,
  `reason`, the running step id, and any failure — not a fabricated step list
  (the runner doesn't expose its steps). No actions in v1.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholeLifecycleTests`, `extraPackageProducts: [PortholeKit, PortholeCore,
LifecycleKit]`). Drive a scripted `LifecycleSteps` and assert the row's phase.
