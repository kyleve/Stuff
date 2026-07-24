# PortholeLifecycle

PortholeLifecycle is a [Porthole](../) connector that exposes an app's launch
state — from the [LifecycleKit](../../LifecycleKit) `LifecycleRunner` it already
owns — so an agent can answer "is the app ready?" before querying other
connectors.

## Using it

```swift
import PortholeLifecycle

// `launchRunner` is the LifecycleRunner your app already drives.
porthole.register(LifecycleConnector(runner: launchRunner))
```

Inject the runner — don't create one. The connector reads it on the main actor.

## Surface (id `lifecycle`)

- Data source `launch-state` — a single row: `phase` (launching / running /
  failed / ready), `reason`, the `runningStep` (when a step is active), and
  `failedStep` + `error` (when the launch failed).

No actions in v1 (retry/teardown actions are on the roadmap).

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholeLifecycleTests`). Drives a scripted `LifecycleSteps` through its phases
and asserts the `launch-state` row tracks launching → ready and a failing step's
failed phase + step/error.
