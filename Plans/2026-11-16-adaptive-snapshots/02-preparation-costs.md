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

Add temporary timers to the existing boundaries and collect the baseline. Refine the design from its evidence before implementation.
