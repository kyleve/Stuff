# 01 — Measure and reduce WebKit readiness waits

- Status: executing
- Depends on: None; begins at PR #511 revision `f4e3b4c8c`.
- Shared context: [Overview](README.md)

## Deliverable

Resolve Q-02 with separate setup, navigation, and paint measurements.
Retain an improvement only if it preserves offline isolation, fresh views, fonts, painted content, and converged height.
This delivers R-01–R-04 for US-01 and retains X-01–X-03.

## Experiment design

Run the 24 InstallerSite captures once with temporary subphase timers.
Compare the dominant wait with the existing WebKit lifecycle and public completion APIs.
Try at most two focused alternatives before deciding whether an improvement is supported.
Retain raw logs outside the repository and concise measurements here; remove temporary timers before publication.
A supported negative result completes the experiment but does not claim a speedup.

## Data flow and architecture

Existing flow: `assertHTMLSnapshots` creates a fresh `SnapshotWebPage`, then the hosted measurement hook awaits navigation, fonts, two animation frames, and height convergence.
The shared capture pipeline owns final settling and PNG comparison.
The initial experiment adds only temporary timers around these existing operations; no architecture or API change is proposed yet.
Any implementation choice requires a recorded Q-02 resolution and updated plan before dependent work.

## Steps

1. Add temporary subphase timers in `Shared/SnapshotKitTesting/Sources/SnapshotWebPage.swift`.
2. Run `./test --no-generate --only ToolsSnapshotTests/InstallerSiteSnapshotTests --timings --record never`.
3. Identify the dominant phase and verify the candidate completion contract from source and primary platform documentation.
4. Update this plan with the selected implementation and failure/cancellation checks, or record a supported negative result.
5. Validate affected WebKit regression tests and all 24 production HTML captures. Compare dimensions, identities, and references.
6. Review the complete diff and publish through `gh stack` with the final integration layer.

## Acceptance and verification

R-01 requires separate setup/navigation/paint evidence and a measured decision.
R-02 requires all existing HTML captures to pass unchanged references and height/edge/font tests to remain valid.
R-03 requires cancellation, failed navigation, unsafe sizing, and non-converging height to keep aborting capture and restoring the host.
R-04 requires publication above PR #511; no independent PR base wiring.

## Recovery

Remove only task-owned temporary instrumentation if an experiment fails.
Do not record references or alter final comparison tolerances to accept a candidate.
Preserve the existing untracked `simple-english` skill.

## Progress and execution record

- 2026-11-16: Reviewed experiment at `f4e3b4c8c`. Source confirms setup occurs outside capture timers and paint convergence inside `measurementHook`.
- Baseline passes all 24 captures. Navigation dominates at roughly 1.7–2.1s per capture; rules and double-frame paint are much smaller. First alternative reuses one ephemeral store within this profiling process, clears all website data before each fresh view, and leaves paint/convergence untouched. The temporary global owner will be removed; any retained implementation must scope ownership to a batch. Apple documents nonpersistent storage and awaited removal of all website data in `WKWebsiteDataStore`.
- Baseline subphases: setup 0.383s (rules 0.173s), navigation 46.192s, 38 paint waits 1.712s across 24 captures. First reuse variant still spends roughly 1.5s per navigation. The second bounded alternative retains the previous stopped page until the next fresh view is constructed, to test process lifetime without reusing page state. Both prototypes clear website data before each view.
- Both reuse alternatives pass all 24 captures but retain roughly 1.5–1.9s navigation waits. No reuse API or global cache is retained. The limited gain does not justify broader storage lifecycle and isolation contracts in this patch. Temporary source changes were removed.
- Pending: publish this negative result with the validated measurement changes and attach the evidence to STU-122.

## Resume point

Publish the measured negative result with plan 02; WebKit production source remains identical to the parent.
