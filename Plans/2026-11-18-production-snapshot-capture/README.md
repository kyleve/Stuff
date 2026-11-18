# Single-mount snapshot capture

Snapshot authors want the ordinary image suite to spend less time waiting for views whose final pixels are already available (US-01). The user requested a production rollout directly against `main`, including images from the earlier trials. [STU-121](https://linear.app/kve/issue/STU-121)

## Scope and evidence

- **R-01** Adopt the faster native paths for verified fixtures from all three cohorts. The first 92 supplied 74 already-immediate components and 14 measured captures. The next 200 supplied 147 measured captures. The last 585 supplied 243.
- **R-02** Preserve measurement readiness, declared minimums, capture hooks, accessibility annotations, scroll and inset corrections, and panel-by-panel comparisons. Keep the ordinary renderer available to each fixture.
- **R-03** Run the normal assertion path on all current references, verify the actual selections by identity, and compare the full-suite runtime on the same simulator.
- **X-01** Reference regeneration, frame caching, and shipping the experimental runner are outside the rollout.

The prototype tested both capture orders. The early measured arm reproduced the live controls exactly for 362 of 404 approved images. The remaining 42 differed by at most two channel levels in eight-bit color. The earlier component arm reproduced all 74 reference PNGs byte for byte. [Component experiment](https://github.com/kyleve/Stuff/blob/59395f313/Plans/2026-11-18-requested-snapshot-frames/03-broader-single-mount.md) · [Suite experiment](https://github.com/kyleve/Stuff/blob/59395f313/Plans/2026-11-18-requested-snapshot-frames/05-suite-coverage.md)

## Decisions and review

| Question | Resolution |
| --- | --- |
| Q-01 (closed, R-01) Which earlier images qualify? | Use distinct reference paths across all three runs. Count the six InstallerKit cards and eight hatched calendars once, in the measured arm. Keep all four Year picker references on their declared floor. |
| Q-02 (closed, R-02) Where is the capture decision made? | The owning test opts in. The renderer checks sizing and readiness. Keep the final wait for WebKit, the iPad Flyover list, and the populated AX5 Presence Timeline. |
| Q-03 (closed, R-03) How does the inventory transfer to main? | Comparing Git objects found 25 new references and 97 updated existing references at `e19c63f77`. Audit these and all selected paths during verification. |

Review of the prototype manifest, fixture registrations and native renderer established the two separate execution paths and their fallbacks. A live main run is the control for the production result.

## Checkpoint

The user authorized planning, implementation, and a ready-for-review PR into main. [01 — Adopt and verify capture](01-adopt-and-verify.md) is the full planning horizon. Work runs on `perf/production-snapshot-capture`. The renderer, component, and fixture owners implement their respective paths. The coordinating agent owns integration, simulator verification, independent review, and publication.
