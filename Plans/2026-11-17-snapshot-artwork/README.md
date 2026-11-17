# Shared snapshot artwork

## Planning checkpoint

- Updated: 2026-11-17; parent PR #514 at `c5cd82626a141df985635868024b159633ce879f`.
- Operation: Execute the user's requested shared artwork cache and preparation changes.
- Scope: One reusable outline-path cache for Where snapshot fixtures, followed by the five identified artwork-hook migrations.
- Stage: Cache implementation validated; preparing the callback migration.
- Completed: Stack checks, baseline, shared-cache implementation, and cache-only focused images. All 18 focused unit tests pass, and the three hosted tests pass again after the review fix.
- Pending: Callback migration, combined measurements, broad image validation, final review, and publication.
- Next action: Commit the verified cache step, migrate the five hooks, and compare the combined result.

## Outcome and requirements

US-01: As a maintainer, I want snapshots to reuse artwork as the app does, with less repeated preparation and waiting.

| ID | Requirement | Plan |
| --- | --- | --- |
| R-01 | Reuse paths by region and resolution throughout the snapshot process, loading only requested geometry. | 01 |
| R-02 | Preserve existing ownership of reports, worlds, navigation, and artwork publication state, with no additional mutable sharing. Preserve cancellation. Keep fresh caches in initial-load unit tests. | 01–02 |
| R-03 | Await artwork before settling where it does not change measured height. Preserve all floors, timeouts, pixel proof, and accessibility passes. | 02 |
| R-04 | Preserve every capture identity, dimension, reference, tolerance, and configured case. | 01–02 |
| R-05 | Measure cache reuse and hook migration separately; publish verified work above PR #514. | 01–02 |

X-01: No additional sharing of mutable fixture worlds or artwork models, eager whole-catalog preload, production cache singleton, or changes to the region geometry algorithms.
X-02: No floor reductions, measurement-policy changes, reference recording, or new global renderer behavior.

## Context and decisions

The user approved sharing immutable artwork after reviewing the remaining performance opportunities. This continues [the adaptive work](../2026-11-16-adaptive-snapshots/README.md) and [STU-121](https://linear.app/kve/issue/STU-121).

`RegionGeometryCatalog.RegionCache` already caches decoded outlines by region. `RegionOutlinePathCache` additionally simplifies and projects paths, keyed only by region and resolution. It rechecks its cache after suspension and never caches a cancelled build. Snapshot declarations currently create many separate actors. `PreviewSupport` is the DEBUG-only fixture composition root and already owns process-lived fixture resources.

Create the shared actor once in `PreviewSupport` and inject it from snapshot composition. Broadway roots must honor an inherited cache instead of replacing it; roots without an inherited cache retain their own actor. This composition change lets nested production and snapshot roots use the same dependency flow. Explicit fresh-cache unit tests keep their ownership. Artwork models keep their existing fixture ownership, and each CI process gets its own cache. Some forecast cases already capture a model outside the per-panel builder; [STU-114](https://linear.app/kve/issue/STU-114/isolate-models-captured-outside-snapshot-builders) owns that pre-existing isolation gap. This change shares only path storage.

The prior full profile records 26.342s in post-settle artwork hooks and their additional settling across 63 captures: Appearance, forecast summary, forecast panel, Locations background, and Region Welcome. The estimated 20–25s saving is from avoiding repeated settling, not a measured caching benefit. The existing APIs and local source establish this design; no external API research is needed.

## Execution order and questions

1. [01 — Shared cache](01-shared-cache.md): preserve initial-load semantics, verify injection, measure the same focused matrix with cache reuse alone.
2. [02 — Preparation hooks](02-preparation-hooks.md): migrate the five identified groups, repeat focused validation, then run full image integration.

| ID | Status | Question | Resolution |
| --- | --- | --- | --- |
| Q-01 | closed | Can fixtures share artwork without sharing their mutable world? | User approved a process-lived path cache. Keys contain region/resolution only; inject at DEBUG snapshot composition, preserve existing model ownership. Broadway roots reuse an inherited cache so nested roots do not replace that dependency. |
| Q-02 | open | How much does cache reuse save separately from hook migration? | Cache-only: 66.223s versus 65.589s baseline, no demonstrated speedup. Reuse and correctness pass. The combined measurement remains pending. |
| Q-03 | open | Do earlier readiness and warm paths preserve pixels and dimensions? | Require unchanged references, matching identities/dimensions, reviewed diagnostics, and full image integration. |

## Plan review

Reviewed 2026-11-17 against `c5cd82626`: composition ownership, actor reentrancy, cache keys, view publication, modifier ordering, cancellation, explicit fixture caches, and image coverage. Plans 01–02 are ready. Guard the actual hosted environment so Broadway cannot silently replace the injected cache. Runtime results remain unverified; the diagram below is source-level design, not rendering evidence.

## Review and delivery

Branch: `perf/snapshot-artwork-cache`, above PR #514 in stack #513. Independent completed-diff review and manual full CI gates are required before handoff. The existing unrelated untracked simple-english skill remains untouched.

## Outcome

In progress. Broader performance work remains in STU-121.
