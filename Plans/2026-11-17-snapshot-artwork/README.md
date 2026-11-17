# Shared snapshot artwork

## Planning checkpoint

- Updated: 2026-11-17; parent PR #514 at `c5cd82626a141df985635868024b159633ce879f`.
- Operation: Execute the user's requested shared artwork cache and preparation changes.
- Scope: One reusable outline-path cache for Where snapshot fixtures, followed by the five identified artwork-hook migrations.
- Stage: Complete; both steps are published in PR #515 above PR #514.
- Completed: Stack checks, baseline, cache-only images, two combined profiles, plus 18 focused unit tests. Three hosted tests pass again after the review fix. Cache step committed at `c42e9456d`; preparation step at `78de9918c`.
- Pending: Remote CI results; dispatch and run links are reported on PR #515.
- Next action: Check CI on PR #515; broader performance work remains in STU-121.

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
| Q-02 | closed | How much does cache reuse save separately from hook migration? | Cache-only: 66.223s versus 65.589s baseline, no demonstrated speedup. Combined profiles take 37.346s and 37.319s (43.1% lower than baseline); readiness relocation provides the measured benefit. |
| Q-03 | closed | Do earlier readiness and warm paths preserve pixels and dimensions? | Both focused runs match all 22 baseline diagnostics; full integration passes 76 tests and 938 captures without retries. No references or tolerances changed. |

## Plan review

Reviewed 2026-11-17 against `c5cd82626`: composition ownership, actor reentrancy, cache keys, view publication, modifier ordering, cancellation, explicit fixture caches, and image coverage. Plans 01–02 are ready. Guard the actual hosted environment so Broadway cannot silently replace the injected cache. Hosted runtime tests and the first two focused image profiles pass. The diagram in plan 01 describes source ownership; image evidence is recorded separately.

Independent review of `c5cd82626..78de9918c` found no remaining source defects. It verified the corrected cache-only/preparation commit boundaries and both raw focused profiles. Review corrected a Swift 6 concurrency warning in the test helper and narrowed the ownership wording to the actual fixture contracts. Full image integration also passes 76 tests and 938 captures without retries; independent review verified the raw full-run results and inventory comparison.

## Review and delivery

Published [PR #515](https://github.com/kyleve/Stuff/pull/515), branch `perf/snapshot-artwork-cache`, above PR #514 in [stack #513](https://github.com/kyleve/Stuff/stack/513). Independent source and evidence review pass. Manual GitHub and CircleCI full gates target the final publication revision; their run links and pending results are recorded on the PR. The existing unrelated untracked simple-english skill remains untouched.

## Outcome

Delivered both steps in PR #515. The targeted 63 captures save 28.243–28.270s (43.1%) in repeated profiles. Shared path storage alone has no demonstrated timing benefit. All 938 full-suite captures pass; simulator evidence does not establish pixel-exact equality for the full matrix. All 22 focused diagnostic payloads match. Broader performance work remains in STU-121, and the pre-existing captured-model isolation gap remains in STU-114.
