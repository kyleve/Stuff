# US and Canadian regions in Where

Where supports Canada's ten provinces and three territories, Canada itself, and the existing 50 US states, Washington, DC, and Puerto Rico. RegionKit reads parent relationships from subdivision metadata. The United States serves as an internal parent. Canada's tracking and artwork come from its 13 children. A maintainer can refresh the boundaries from their publishers for use offline.

## Planning checkpoint

- **Operation and authority.** On November 25, 2026, the owner directly requested removal of the separate US and Canadian country outlines on the existing [implementation PR #563](https://github.com/kyleve/Stuff/pull/563). [Q-04](#questions-and-resolutions) records the change to the prior decision. The work belongs to [STU-348](https://linear.app/kve/issue/STU-348).
- **Current horizon.** All four plans are complete. The November 25 revision began at PR head `c94ce9640` on `codex/north-american-regions` in the shared Stuff worktree. The implementation is in review on [PR #563](https://github.com/kyleve/Stuff/pull/563).
- **Owners and handoff.** The release worker (`global`) verified conversion, generation and replay. The geometry worker (`canada`) verified child-derived geography. The plan worker (`europe`) reviewed the implementation and verified the visual results. The coordinator owns integration, publication and PR follow-up. [Plan 04](04-country-geometry.md#execution-record-and-resume-point) records the measured results.
- **Earlier delivery.** The November 18 research covered the US, Canada and EU. The November 22 request selected North America and plan publication. [Planning PR #560](https://github.com/kyleve/Stuff/pull/560) recorded the November 24 decision to store both country outlines. Plans [01](01-region-hierarchy.md), [02](02-boundary-updater.md) and [03](03-ship-regions.md) were verified on PR #563 in `522a032df`, `0cb45316f`, `a6e0bea86` and `c94ce9640`. Their 68-file release, 1,754 executed unit tests and 438 image references across 27 suites are the baseline for this revision.

## User stories

| ID | Outcome |
| --- | --- |
| S-01 | A traveler can select Ontario and Canada in the existing flat list. A Toronto GPS fix credits Ontario. A Vancouver fix credits Canada when British Columbia is untracked. Someone tracking only Canada keeps country-level results. |
| S-02 | A RegionKit consumer can ask which country contains California or Nunavut, what kind of jurisdiction it is, and which direct children the country has. The consumer can use Canada as one region and the US as catalog metadata. Manual entries and corrections keep the precision the user recorded. |
| S-03 | A maintainer can reproduce the checked-in catalog or evaluate a new publisher release, see what changed and retry a failed refresh safely. The installed app works offline. |

## Requirements

| ID | Required behavior | Story | Deliverable |
| --- | --- | --- | --- |
| R-01 | Resolve each subdivision’s country directly from its parent ID and enumerate the parent’s direct children. Preserve jurisdiction kinds, raw IDs and eligibility. Both country nodes are metadata-only in the manifest. The US has 52 catalog children and Canada has 13. | S-02 | [01](01-region-hierarchy.md), [03](03-ship-regions.md), [04](04-country-geometry.md) |
| R-02 | Return the most specific matching tracked region per fix. Live GPS confidence accounts for an accuracy circle crossing into or out of that region. Preserve existing country-only tracking, manual assertions, and same-day credit from separate observations. Offer the supported Canadian choices through the normal flat workflows. | S-01, S-02 | [01](01-region-hierarchy.md), [03](03-ship-regions.md), [04](04-country-geometry.md) |
| R-03 | Provide one documented, version-aware maintainer entry point with deterministic generation, cached/offline replay, explicit upstream refresh and failure recovery. | S-03 | [02](02-boundary-updater.md), [04](04-country-geometry.md) |
| R-04 | Use official WGS84-transformed boundary data, stable source-to-app ID mapping, traceable licences and reproducible inputs. Validate geographic detail, size and runtime cost before bundling. | S-01, S-03 | [02](02-boundary-updater.md), [03](03-ship-regions.md), [04](04-country-geometry.md) |
| R-05 | Ship the 52 US jurisdictions, all 13 Canadian subdivisions and the existing EU outline as 66 geometry files. Derive Canadian membership, exterior and hole boundaries, map and artwork from its children. Keep the US metadata-only and the 67 available region IDs stable. Credit the geometry actually supplied. | S-01, S-02, S-03 | [03](03-ship-regions.md), [04](04-country-geometry.md) |

## Scope boundaries

| ID | Boundary |
| --- | --- |
| X-01 | Preserve existing EU bloc behavior and geometry. Keep US tracking limited to the current 52 jurisdictions. The four additional Census records (AS, GU, MP and VI) stay outside the app catalog. Other remains the sentinel. |
| X-02 | Keep existing lists, search, maps and manual entry. Hierarchical browsing, breadcrumbs and parent/child labels are excluded. |
| X-03 | A single GPS fix earns one region. This work excludes automatic ancestor day totals, assigning subdivisions to historic manual entries or corrections, and rewriting raw observations. Existing read-time GPS attribution still uses the current tracked set and geometry. |
| X-04 | Source downloads happen on a maintainer's machine. Runtime downloads, location lookups against a server and scheduled update jobs are outside scope. |

## Findings at the start of planning

- The original catalog contained 54 geometry files totaling 2,156,498 bytes. The default attributor loaded four regions. The decoder discarded interior rings. The live resolver used distance to the boundary when testing GPS accuracy. [RegionKit](../../Where/RegionKit/README.md), [GeoJSON reader](../../Where/RegionKit/Sources/GeoJSON.swift), [live resolver](../../Where/WhereCore/Sources/Location/CurrentRegionResolver.swift)
- RegionKit's public raw-value initializer validates input. Its Codable representation is a bare string. Some store and forecasting reads still validate against the installed catalog, so an older build can discard a newly introduced ID even though the wire shape is identical. Plan 03 addresses mixed-version access before the first new ID is written. [Region](../../Where/RegionKit/Sources/Region.swift), [store](../../Where/WhereCore/Sources/Persistence/SwiftDataStore.swift), [account compatibility version](../../Where/WhereCore/Sources/Compatibility/DataModelVersion.swift)
- The original primary picker filtered IDs by `us-`. The Settings editor could drop a saved Canada selection, and forecasting used the same US list. Plan 03 supplied flat US and Canadian choices to these workflows. [Primary picker](../../Where/WhereUI/Sources/Regions/PrimaryRegionSelectionModel.swift), [forecast picker](../../Where/WhereUI/Sources/Forecasting/PlanningRegionSelectionModel.swift)
- US Census publishes a versioned national state/equivalent ZIP. Use its 2026 TIGER/Line release and postal codes to carry existing IDs forward. StatCan's 2026 detailed cartographic layer supplies land and coastal islands, English and French names, and all 13 PRUIDs. Map those IDs explicitly to `ca-ON`, `ca-NT`, etc. Its service assigns the Open Government Licence – Canada. These are the selected sources from the research. The Canadian choice follows the land-based logging recommendation. Boats in coastal waters can fall outside that layer. [US archive](https://www2.census.gov/geo/tiger/TIGER2026/STATE/), [Canadian product definitions](https://www150.statcan.gc.ca/n1/daily-quotidien/261118/dq261118f-eng.htm), [province and territory layer](https://geo.statcan.gc.ca/geo_wa/rest/services/2026/Cartographic_boundary_files/MapServer/0), [licence](https://open.canada.ca/en/open-government-licence-canada/)
- The selected Census source contains 56 state and equivalent records, including American Samoa, Guam, the Northern Mariana Islands and the US Virgin Islands. Only the existing 52 US jurisdictions become catalog children. The US Minor Outlying Islands are outside this source's coverage. [Census geographic coverage](https://www2.census.gov/geo/pdfs/maps-data/data/tiger/tgrshp2026/TGRSHP2025_TechDoc_Ch2.pdf)
- Canada is both a country that can be logged and the parent of ten provinces and three territories. Canada-only confidence must use the combined exterior and holes of its 13 subdivisions so an internal provincial border does not reduce confidence in a Canada-only fix. When Ontario is also tracked, the same border can change the winner on either side. A named planned stay in Canada still accepts a fix inside Ontario.

## Execution order and planning horizon

| Order | Plan | Outcome |
| --- | --- | --- |
| 1 | [Catalog relationships and attribution](01-region-hierarchy.md) | Completed November 24. Fixtures demonstrated parent links, stored country outlines and single-region lookup. The existing production IDs retain their order. |
| 2 | [Reusable boundary updater](02-boundary-updater.md) | A maintainer can produce a verified candidate from official vintages, without activating new app regions. |
| 3 | [Ship and verify the catalog](03-ship-regions.md) | The app consumes the approved resources, credits their sources and supports the new regions in its existing workflows. |
| 4 | [Derive country behavior from subdivisions](04-country-geometry.md) | Replace both stored country files while retaining the existing regional and country-level workflows. |

The first two deliverables supplied the fixture results and repeatable source release used to qualify the third. Plan 03 records the accepted simplification settings, file sizes, topology checks and measured lookup costs.

## Questions and resolutions

| ID | Status | Resolution and source | Impact and integration |
| --- | --- | --- | --- |
| Q-01 | closed | On November 22 the user chose the most specific tracked region. A Toronto fix earns Ontario alone if Ontario and Canada are tracked. | Integrated in S-01, R-02 and Plans 01/03. Manual Canada records keep their existing meaning. |
| Q-02 | closed | On November 22 the user chose an internal United States parent and the current set of US tracking choices. | Integrated in R-01, R-05, X-01 and all three plans. The US node is ineligible for selection. Q-04 records the change to metadata-only US behavior. |
| Q-03 | closed | On November 22 the user chose to publish the plan for review first. | Planning review was published first. The owner authorized execution on November 24. |
| Q-04 | closed | On November 24 the owner required consistent country handling. The first delivery stored both outlines. On November 25 the owner withdrew that choice because the separate geometry is redundant. | [04](04-country-geometry.md) replaces the former design in R-01, R-04 and R-05. Country relationships come from child metadata. The US is internal. Canada remains selectable and derives its geography from its children. |

## Plan review and delivery

- November 22, 2026, `acdae322d`. Review identified tracked-child accuracy on both sides of a border, interrupted adoption, and compatibility for older backup and account readers. Plans 01 and 02 supplied the fixture and release evidence used to refine 03. [Planning PR #560](https://github.com/kyleve/Stuff/pull/560)
- November 24, 2026. The owner requested a consistent country-outline policy. The original execution produced national files from the full source memberships. The three completed plans preserve that decision, implementation, measurements and checks. [Original review comment](https://github.com/kyleve/Stuff/pull/560#discussion_r4685927230)
- November 25, 2026, starting at `c94ce9640`. Reviewed the revised data flow and inventory against the current consumers, the stable IDs and Q-01 through Q-04. All four Mermaid diagrams rendered and all local plan targets resolved. The direct request replaces the previous US outline lookup and both national resources. [Plan 04](04-country-geometry.md) owns the repeat verification for country confidence, drawings, physical resources and update replay.
