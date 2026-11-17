# 02 — Locate adaptive fixture preparation costs

- Status: executing
- Depends on: None; shares the serial baseline with plan 01
- Shared requirements and exclusions: [Overview](README.md)

## Deliverable and experiment bounds

Resolve Q-02 with separate demo scope construction, session startup, report activation, and artwork measurements.
This addresses R-01–R-04 and preserves X-01–X-03.
Add temporary timers to `WhereFlyoverWorld.build()` and `DuoLayoutSnapshotFixture.prepare()`. Do not confuse concurrent callers' overlapping elapsed time with summed capture time.
Use the complete MainTabs matrix. Keep both the hosted task and readiness hook unchanged while profiling.

After the baseline, inspect the dominant stage and refine this plan before retaining a preparation change.
Try at most two focused alternatives that preserve fresh worlds, report contents, production-shaped services, preview startup, errors, and cancellation.
A supported negative result completes the experiment. Remove all temporary timers before publication.

## Existing flow and ownership

Each adaptive configuration owns `DuoLayoutSnapshotFixture`, its `WhereDemoWorldModel`, and its outline cache.
The model builds one `WhereFlyoverWorld`: a demo scope, started session, model, and activated report.
The scene displays the loaded world, then the capture pipeline awaits artwork and settles native chrome.
The temporary timers observe those boundaries only; no new API or architecture is proposed.

## Verification and recovery

Use plan 01's baseline command and the same focused matrix for candidates.
A retained shared-world implementation also needs its existing lifecycle/fixture tests and affected image consumers, selected from actual call sites.
Compare identities, dimensions, reference output, failure behavior, and measured subphases.
Reject shared mutable-world reuse across configurations. Restore temporary source edits if evidence does not support a simpler implementation.
Record the measured conclusion here and in STU-121; keep raw logs outside Git.

## Resume point

Profiling is complete and temporary source changes are removed. Publish the measured negative result with plan 01 after independent review.

## Initial profiling evidence

The 1.5s baseline passes all 61 captures without retries. Its 39 worlds spend 24.776s creating scopes, 10.252s starting sessions, and 5.210s activating reports. Capture preparation totals 46.159s. There are 78 preparation callers; their load/wait/artwork timers overlap and must not be added. One caller repeatedly yields for roughly a second while the other constructs the world.

Before selecting a retained change, run five isolated fixture preparations through one caller, with the same timers and fresh worlds. This bounded diagnostic distinguishes useful construction work from contention caused by the readiness waiter. It does not establish capture readiness or authorize a global cache. No lifecycle implementation changes are selected yet.

The isolated probe passes five fresh-world preparations. Total load time is 4.985s (median 0.926s): scopes 3.068s, sessions 1.271s, and reports 0.641s; artwork takes 0.148s. No caller spins waiting for another load. Construction still takes roughly a second, so this probe does not support a large saving from replacing the readiness waiter. It also omits the mounted scene, so the small timing difference cannot be assigned solely to polling.

Decision: retain the current world lifecycle and preparation APIs. Scope creation performs the real demo seed, session startup reconciles the seeded services, and report activation reads the loaded world. Reducing those costs needs further work on the underlying operations; sharing worlds or replacing them with lighter fixtures would violate this experiment's isolation and content requirements. Record those subphase costs in STU-121. Remove temporary timers and the isolated probe before final verification.
