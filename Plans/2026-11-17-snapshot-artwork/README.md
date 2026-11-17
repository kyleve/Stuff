# Shared snapshot artwork

## Planning checkpoint

- Updated: 2026-11-17; parent PR #514 at `c5cd82626a141df985635868024b159633ce879f`.
- Operation: Execute the user's requested shared artwork cache and preparation changes.
- Scope: One reusable outline-path cache for Where snapshot fixtures, followed by the five identified artwork-hook migrations.
- Stage: Plan reviewed; baseline measurement running.
- Completed: Stack and feedback checks; all three parent PRs are green and mergeable. Source geometry already caches per process.
- Pending: Implementation, matched measurements, image validation, independent review, and publication.
- Next action: Finish the 63-capture baseline, then implement plan 01.

## Outcome and requirements

US-01: As a maintainer, I want snapshots to reuse artwork as the app does, with less repeated preparation and waiting.

| ID | Requirement | Plan |
| --- | --- | --- |
| R-01 | Reuse paths by region and resolution throughout the snapshot process, loading only requested geometry. | 01 |
| R-02 | Preserve independent reports, worlds, navigation, artwork publication state, and cancellation. Keep fresh caches in initial-load unit tests. | 01–02 |
| R-03 | Await artwork before settling where it does not change measured height. Preserve all floors, timeouts, pixel proof, and accessibility passes. | 02 |
| R-04 | Preserve every capture identity, dimension, reference, tolerance, and configured case. | 01–02 |
| R-05 | Measure cache reuse and hook migration separately; publish verified work above PR #514. | 01–02 |

X-01: No shared mutable fixture worlds or artwork models, eager whole-catalog preload, production cache singleton, or changes to the region geometry algorithms.
X-02: No floor reductions, measurement-policy changes, reference recording, or new global renderer behavior.

## Context and decisions

The user approved sharing immutable artwork after reviewing the remaining performance opportunities. This continues [the adaptive work](../2026-11-16-adaptive-snapshots/README.md) and [STU-121](https://linear.app/kve/issue/STU-121).

`RegionGeometryCatalog.RegionCache` already caches decoded outlines by region. `RegionOutlinePathCache` additionally simplifies and projects paths, keyed only by region and resolution. It rechecks its cache after suspension and never caches a cancelled build. Snapshot declarations currently create many separate actors. `PreviewSupport` is the DEBUG-only fixture composition root and already owns process-lived fixture resources.

Create the shared actor once in `PreviewSupport` and inject it from snapshot composition. Production views continue to consume their environment dependency; the shipping Broadway root and explicit fresh-cache unit tests keep their existing ownership. This shares deterministic render data while each view retains its own `RegionArtworkModel`. Each CI process gets its own cache.

The prior full profile records 26.342s in post-settle artwork hooks and their additional settling across 63 captures: Appearance, forecast summary, forecast panel, Locations background, and Region Welcome. The estimated 20–25s saving is from avoiding repeated settling, not a measured caching benefit. The existing APIs and local source establish this design; no external API research is needed.

## Execution order and questions

1. [01 — Shared cache](01-shared-cache.md): preserve initial-load semantics, verify injection, measure the same focused matrix with cache reuse alone.
2. [02 — Preparation hooks](02-preparation-hooks.md): migrate the five identified groups, repeat focused validation, then run full image integration.

| ID | Status | Question | Resolution |
| --- | --- | --- | --- |
| Q-01 | closed | Can fixtures share artwork without sharing their mutable world? | User approved a process-lived path cache. Keys contain region/resolution only; inject at DEBUG snapshot composition, keep models independent. |
| Q-02 | open | How much does cache reuse save separately from hook migration? | Compare baseline, cache-only, and combined focused runs. A small measured cache gain is acceptable if reuse and correctness are established. |
| Q-03 | open | Do earlier readiness and warm paths preserve pixels and dimensions? | Require unchanged references, matching identities/dimensions, reviewed diagnostics, and full image integration. |

## Plan review

Reviewed 2026-11-17 against `c5cd82626`: composition ownership, actor reentrancy, cache keys, view publication, modifier ordering, cancellation, explicit fixture caches, and image coverage. Plans 01–02 are ready. Guard the actual hosted environment so Broadway cannot silently replace the injected cache. Runtime results remain unverified; the diagram below is source-level design, not rendering evidence.

## Review and delivery

Branch: `perf/snapshot-artwork-cache`, above PR #514 in stack #513. Independent completed-diff review and manual full CI gates are required before handoff. The existing unrelated untracked simple-english skill remains untouched.

## Outcome

In progress. Broader performance work remains in STU-121.
