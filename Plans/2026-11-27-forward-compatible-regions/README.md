# Keep Where usable when its region catalog is older

Adding a region should let people keep using the version of Where they already have. Once a build can preserve unknown IDs, it can open history and record visits against an older catalog. If a saved ID is missing from its bundled catalog, Where displays **Unknown region** and keeps the original ID. Updating the catalog supplies the name without rewriting the record.

## Planning checkpoint

November 27, 2026 · source `2f639e987` · [STU-349](https://linear.app/kve/issue/STU-349/keep-where-usable-when-its-catalog-lacks-a-saved-region). The owner requested a plan following the Canadian release. Discovery and both product decisions are complete. Both numbered plans are ready for review and execution in order. Implementation awaits a separate request.

## What the user experiences

Consider a manual day tagged with California and a future region named North Coast. The example uses the same day and IDs throughout. North Coast is an illustrative test fixture.

| Action | What the user sees | What Where stores |
| --- | --- | --- |
| Open the day with a tolerant build whose catalog lacks North Coast | California · Unknown region | `us-CA`, `test-north` |
| Edit its note, close the app, then reopen or restore its backup | The edited note and the same two regions | `us-CA`, `test-north` |
| Open the same data with a catalog that includes North Coast | California · North Coast | `us-CA`, `test-north` |

Someone whose history and settings use only familiar regions sees no change. With two unfamiliar regions, each keeps its own history and count even though both have the same label. A day explicitly logged as **Other** keeps that meaning. GPS samples store coordinates. Their automatic attribution can improve when the installed catalog gains geometry. Manual entries and sample corrections retain their existing precedence.

## Stories, requirements and execution order

- **US-01** — An established user can keep recording, reviewing history and editing familiar regions when their catalog is older.
- **US-02** — A user can edit a note, restore a backup, and later see the original region’s name and history on an updated build.
- **US-03** — A maintainer can ship another region while reserving the lockout for changes that older supported clients cannot safely interpret.

| ID | Required outcome | Stories | Deliverable |
| --- | --- | --- | --- |
| R-01 | Preserve each well-formed, unfamiliar ID in existing fields. Keep it distinct from other unfamiliar IDs, the Other sentinel, absent values and retired country selections. | US-01, US-02 | [01 · Stored identities](01-preserve-stored-regions.md) |
| R-02 | Reads, writes, backup export, merge and replace preserve the IDs with their records, metadata and revision semantics. | US-02 | [01](01-preserve-stored-regions.md) |
| R-03 | Recording and known geometry work with a partially or wholly unfamiliar tracked set. A missing boundary cannot justify a permanent attribution or correction. | US-01 | [01](01-preserve-stored-regions.md), [02 · Everyday use and release](02-use-an-older-catalog.md) |
| R-04 | Render “Unknown region” wherever the saved region is shown. Preserve its counts and selection through unrelated edits. New choices come from the locally supported catalog. | US-01, US-02 | [02](02-use-an-older-catalog.md) |
| R-05 | Prove compatibility between two catalogs at account v2 and archive v8. Document when the same-version rule applies and retain the gates for incompatible changes. | US-03 | [02](02-use-an-older-catalog.md) |

Both plans are in the current horizon. The first makes unknown IDs safe to read, write and restore. The second uses that contract in the app and extensions and qualifies it for release. Review the first plan’s test results before starting the second. The safe release includes both.

**Scope boundaries.** **X-01** excludes adding regions, downloading boundaries and guessing a region from its ID. **X-02** excludes a new storage schema, a global “unknown” ID, migration of healthy history, or retrospective repair of data already lost. **X-03** excludes changing the compatibility coordinator, lowering existing floors or re-enabling older Canadian-incompatible builds. Renames that repurpose an ID, removals, changes in eligibility or attribution meaning, and new record shapes require a separate compatibility assessment.

## Evidence and release decision

| Observation at the source revision | Design consequence |
| --- | --- |
| The Canadian release advanced the account to v2 and portable backups to v8. Eligible recorders can publish a higher account version during verification before someone chooses a new region. A portable ZIP has its own exact-version check. [Canadian release](https://github.com/kyleve/Stuff/pull/563) · [Publication protocol](../../Where/Specifications/CompatibilityPublication/README.md) · [Backup format](../../Where/WhereCore/BACKUP_FORMAT.md) | The owner confirmed Where runs on one phone and no older builds will exist. Install the tolerant app and its extensions there before introducing any new writable ID or importing such a ZIP. Keep v2 and v8. Those numbers alone cannot identify a tolerant binary. |
| Codable already round-trips a bare ID string. Catalog lookup validates loggable membership, and an unresolved name currently falls back to the raw ID. The store uses that same membership check to reconstruct rows. [Region](../../Where/RegionKit/Sources/Region.swift) · [Catalog](../../Where/RegionKit/Sources/RegionCatalog.swift) · [Store](../../Where/WhereCore/Sources/Persistence/SwiftDataStore.swift) | Separate “was stored” from “can be chosen here.” Let catalog membership supply a name and capabilities when available. Keep known metadata-only parents subject to the [existing country policy](../2026-11-22-north-american-regions/05-country-parents.md). |
| A primary-region save deletes omitted rows. The manual-day editor also builds a saved set from the toggles it can show. Mapping an unrecognized ID to Other would merge independent regions and can change how Elsewhere interprets a visit. [Primary editor](../../Where/WhereUI/Sources/Regions/PrimaryRegionSelectionModel.swift) · [Day selection](../../Where/WhereUI/Sources/Shared/RegionSelectionState.swift) · [Elsewhere](../../Where/WhereCore/Sources/Reporting/ElsewhereResolver.swift) | A label change alone would leave destructive writes in place. Exercise real edits and both backup strategies using data from a different catalog. |

The alternative of publishing a new floor once would protect strict clients in a mixed installed base. The owner’s single-installation rollout makes that transition unnecessary. If a strict v2 build will run again or receive a future-ID v8 archive, revisit admission **before** any such write or transfer. The relevant behavior is owned by this repository and its tests.

## Questions and resolutions

| ID | Status | Answer and integration |
| --- | --- | --- |
| Q-01 | closed | November 27. Asked which fallback to show on the older build. The owner chose “Unknown region” and preservation on edits. Incorporated in the example, R-01–04 and both plans. |
| Q-02 | closed | November 27. Asked how to protect strict installed builds during rollout. The owner confirmed only their phone runs Where and no older build will exist. R-05 and plan 02 use install order at v2/v8. |

## Plan review

November 27, 2026. Reviewed both deliverables against the Canadian release, current source and the owner’s answers. Independent review identified data loss on additive range backfills and ambiguity between retired countries and missing entries. The revised checks cover both cases and exercise production name lookup across two catalogs. Both diagrams rendered, local links and anchors resolved, and the dependency order is acyclic. No app behavior was tested during planning.
