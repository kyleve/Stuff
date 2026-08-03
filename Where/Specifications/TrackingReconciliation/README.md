# Tracking reconciliation TLA+ pilot

This is an executable design experiment for the tracking-toggle race in
[`WhereSession`](../../WhereUI/Sources/Model/WhereSession.swift). It asks one
small question: after rapid enable/disable commands and all asynchronous work
settles, do persisted intent, the real ingestor, and the UI's published state
all describe the latest command?

It is deliberately not a repository-wide TLA+ convention, nor a proof of the
Swift implementation. The model is useful only while its state and transitions
remain visibly traceable to the production code and a deterministic test.

## Model boundary

| Model state | Production counterpart |
| --- | --- |
| `desired` | Latest value assigned by the toggle |
| `persisted` | `WherePreferences.wantsTracking` |
| `ingestorActive` | `LocationIngestor.isActive` |
| `published` | `WhereSession.isTracking` |
| Broken command phase | Independent `Task` spawned by `trackingEnabled` |
| Coalesced worker / target | One serialized worker and the intent captured for its in-flight effect |

The checked command sequence is `enable, disable`, authorization is fixed at
Always, and weak fairness forces the configured commands to arrive and each
enabled asynchronous phase eventually to return. Permission UI, authorization
changes, GPS samples, persistence failures, and task cancellation are outside
this first model.

The safety condition is intentionally about quiescence: once every submitted
command has settled, persisted intent must equal the latest command, and the
ingestor and published UI state must equal that intent gated by authorization.
The liveness property says the system eventually reaches that matching state.

## What it found

[`Broken.cfg`](Broken.cfg) is expected to violate `CorrectAtQuiescence`. TLC
finds an ordering corresponding to the real actor-reentrancy boundary:

1. Enable begins and enters `LocationIngestor.start()`.
2. The ingestor marks itself active before its `LocationSource.start()` await.
3. Disable runs during that await, persists `false`, stops the ingestor, and
   publishes `false`.
4. The older enable resumes and unconditionally publishes `true`.

The final state is therefore `desired = false`, `persisted = false`, and
`ingestorActive = false`, but `published = true`. The deterministic expected-
failure guard in
[`WhereSessionTrackingTests`](../../WhereUI/Tests/WhereSessionTrackingTests.swift)
holds the real implementation at exactly that await.

[`Coalesced.cfg`](Coalesced.cfg) checks the proposed design: record intent
synchronously, allow at most one side effect in flight, and rerun the worker if
intent changed while it awaited. That model satisfies the type,
immediate-intent, quiescent-correctness, and eventual-settlement properties for
the same command sequence. The worker is a system-wide lane: toggle writes,
launch and foreground reconciliation, authorization observation, and permission
completion must all join it. Serializing only the toggle setter would not
implement the modeled design.

This is design evidence, not yet the product fix. Implementing the worker should
make the Swift guard pass without `withKnownIssue`; changing the design should
change this model first so its assumptions remain explicit.

## Run it

From this directory:

```sh
./check
```

The checker pins TLC 1.7.4 by SHA-256 and Eclipse Temurin 21.0.8+9 through
`mise`. It caches both under the repository's ignored `.build/tla/` directory.
A clean first run needs network access and downloads about 350 MB, almost all of
it the JDK. Each run keeps its TLC log and state under `.build/tla/runs/`. A
successful run means the broken model failed for the expected invariant and the
coalesced model completed without an error. The pilot is opt-in and is not wired
into CI.
