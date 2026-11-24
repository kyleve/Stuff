# US and Canadian regions in Where

Where users can log any of Canada's ten provinces and three territories and continue tracking Canada as a whole. US tracking keeps its current 50 states, Washington, DC, and Puerto Rico. Every country in RegionKit has a boundary file. A caller can look up the US outline through the catalog even though Where offers only its 52 supported jurisdictions for tracking. Maintainers can refresh the offline boundaries from their publishers with one documented tool.

## Planning checkpoint

- November 22, 2026. Plan creation on `plan/north-american-regions`, based on `acdae322d`. Selected work is tracked in [STU-348](https://linear.app/kve/issue/STU-348).
- The November 18 research compared US, Canada and EU sources. The November 22 request selected the US, Canada, a reusable updater and internal relationships. The user has confirmed that this pass ends with a published plan for review.
- November 24 revision following owner review of PR #560. The plan now requires an outline for every country independently of tracking eligibility. The US outline and its production parent links ship together.
- November 24 execution. The owner approved all three steps. The implementation branch `codex/north-american-regions` is based on the reviewed plan at `2dc4b33a8`. The only [inline feedback](https://github.com/kyleve/Stuff/pull/560#discussion_r4685927230) concerned the US outline and is incorporated in Q-04.
- All three plans are complete on [implementation PR #563](https://github.com/kyleve/Stuff/pull/563). [Plan 01](01-region-hierarchy.md) shipped the hierarchy in `522a032df`. [Plan 02](02-boundary-updater.md) shipped the updater in `0cb45316f`. [Plan 03](03-ship-regions.md) published the official boundaries and app integration in `a6e0bea86`. Offline replay reproduced the installed release. All 1,754 executed simulator unit tests passed, and the UI checks covered 438 references across 27 suites. The linked STU-348 issue remains in review.

## User stories

| ID | Outcome |
| --- | --- |
| S-01 | A traveler can select Ontario and Canada in the existing flat list. A Toronto GPS fix credits Ontario. A Vancouver fix credits Canada when British Columbia is untracked. Someone tracking only Canada keeps country-level results. |
| S-02 | A RegionKit consumer can ask which country contains California or Nunavut, what kind of jurisdiction it is, and which direct children the country has. The consumer can request either country’s outline by catalog node. Manual entries and corrections keep the precision the user recorded. |
| S-03 | A maintainer can reproduce the checked-in catalog or evaluate a new publisher release, see what changed and retry a failed refresh safely. The installed app works offline. |

## Requirements

| ID | Required behavior | Story | Deliverable |
| --- | --- | --- | --- |
| R-01 | Add explicit, validated, bidirectional catalog relationships and local jurisdiction kinds. Keep existing raw IDs and require an outline for every country node. Give callers an explicit outline lookup independent of logging eligibility. | S-02 | [01](01-region-hierarchy.md), [03](03-ship-regions.md) |
| R-02 | Return the most specific matching tracked region per fix. Live GPS confidence accounts for an accuracy circle crossing into or out of that region. Preserve existing country-only tracking, manual assertions, and same-day credit from separate observations. Offer the supported Canadian choices through the normal flat workflows. | S-01, S-02 | [01](01-region-hierarchy.md), [03](03-ship-regions.md) |
| R-03 | Provide one documented, version-aware maintainer entry point with deterministic generation, cached/offline replay, explicit upstream refresh and failure recovery. | S-03 | [02](02-boundary-updater.md) |
| R-04 | Use official WGS84-transformed boundary data, stable source-to-app ID mapping, traceable licences and reproducible inputs. Validate geographic detail, size and runtime cost before bundling. | S-01, S-03 | [02](02-boundary-updater.md), [03](03-ship-regions.md) |
| R-05 | Ship outlines for the US and Canada, all 13 Canadian subdivisions and the 52 existing US jurisdictions. Preserve island and hole semantics, country boundary distance and saved records. Credit the data in Settings and in the repository. | S-01, S-02, S-03 | [03](03-ship-regions.md) |

## Scope boundaries

| ID | Boundary |
| --- | --- |
| X-01 | Preserve existing EU bloc behavior and geometry. Keep US tracking limited to the current 52 jurisdictions. Other Census state equivalents contribute only to the country outline. |
| X-02 | Keep existing lists, search, maps and manual entry. Hierarchical browsing, breadcrumbs and parent/child labels are excluded. |
| X-03 | A single GPS fix earns one region. This work excludes automatic ancestor day totals, assigning subdivisions to historic manual entries or corrections, and rewriting raw observations. Existing read-time GPS attribution still uses the current tracked set and geometry. |
| X-04 | Source downloads happen on a maintainer's machine. Runtime downloads, location lookups against a server and scheduled update jobs are outside scope. |

## Findings at the start of planning

- The generated catalog contains 54 geometry files totalling 2,156,498 bytes. The default attributor loads four regions. The live service reloads only its tracked set. The geometry decoder drops interior rings, and the current resolver uses distance to the boundary when testing GPS accuracy. [RegionKit](../../Where/RegionKit/README.md), [GeoJSON reader](../../Where/RegionKit/Sources/GeoJSON.swift), [live resolver](../../Where/WhereCore/Sources/Location/CurrentRegionResolver.swift)
- RegionKit's public raw-value initializer validates input. Its Codable representation is a bare string. Some store and forecasting reads still validate against the installed catalog, so an older build can discard a newly introduced ID even though the wire shape is identical. Plan 03 addresses mixed-version access before the first new ID is written. [Region](../../Where/RegionKit/Sources/Region.swift), [store](../../Where/WhereCore/Sources/Persistence/SwiftDataStore.swift), [account compatibility version](../../Where/WhereCore/Sources/Compatibility/DataModelVersion.swift)
- The primary picker filters IDs by `us-`. The settings editor can remove a saved Canada selection on save, and forecasting reuses the same US list. New files alone would leave the provinces unavailable for automatic tracking. Conversely, passing the entire hierarchy to these consumers would expose the internal US country and change EU eligibility. [Primary picker](../../Where/WhereUI/Sources/Regions/PrimaryRegionSelectionModel.swift), [forecast picker](../../Where/WhereUI/Sources/Forecasting/PlanningRegionSelectionModel.swift)
- US Census publishes a versioned national state/equivalent ZIP. Use its 2026 TIGER/Line release and postal codes to carry existing IDs forward. StatCan's 2026 detailed cartographic layer supplies land and coastal islands, English and French names, and all 13 PRUIDs. Map those IDs explicitly to `ca-ON`, `ca-NT`, etc. Its service assigns the Open Government Licence – Canada. These are the selected sources from the research. The Canadian choice follows the land-based logging recommendation. Boats in coastal waters can fall outside that layer. [US archive](https://www2.census.gov/geo/tiger/TIGER2026/STATE/), [Canadian product definitions](https://www150.statcan.gc.ca/n1/daily-quotidien/261118/dq261118f-eng.htm), [province and territory layer](https://geo.statcan.gc.ca/geo_wa/rest/services/2026/Cartographic_boundary_files/MapServer/0), [licence](https://open.canada.ca/en/open-government-licence-canada/)
- Build each country outline by merging its publisher’s subdivision polygons and removing their shared edges. The US outline uses all 56 state and equivalent features in the 2026 release, including American Samoa, Guam, the Northern Mariana Islands and the US Virgin Islands. Only the 50 states, DC and Puerto Rico become catalog children. The US Minor Outlying Islands are outside this source’s coverage. [Census geographic coverage](https://www2.census.gov/geo/pdfs/maps-data/data/tiger/tgrshp2026/TGRSHP2025_TechDoc_Ch2.pdf)
- Canada is both a country that can be logged and the parent of ten provinces and three territories. The country geometry needs a real exterior boundary so an internal provincial border does not reduce confidence in a Canada-only fix. When Ontario is also tracked, the same border can change the winner on either side. A named planned stay in Canada still accepts a fix inside Ontario.

## Execution order and planning horizon

| Order | Plan | Outcome |
| --- | --- | --- |
| 1 | [Catalog relationships and attribution](01-region-hierarchy.md) | Fixtures demonstrate parent links, on-demand country outlines and single-region lookup. The existing production IDs retain their order. |
| 2 | [Reusable boundary updater](02-boundary-updater.md) | A maintainer can produce a verified candidate from official vintages, without activating new app regions. |
| 3 | [Ship and verify the catalog](03-ship-regions.md) | The app consumes the approved resources, credits their sources and supports the new regions in its existing workflows. |

The first two deliverables supplied the fixture results and repeatable source release used to qualify the third. Plan 03 records the accepted simplification settings, file sizes, topology checks and measured lookup costs.

## Questions and resolutions

| ID | Status | Resolution and source | Impact and integration |
| --- | --- | --- | --- |
| Q-01 | closed | On November 22 the user chose the most specific tracked region. A Toronto fix earns Ontario alone if Ontario and Canada are tracked. | Integrated in S-01, R-02 and Plans 01/03. Manual Canada records keep their existing meaning. |
| Q-02 | closed | On November 22 the user chose an internal United States parent and the current set of US tracking choices. | Integrated in R-01, R-05, X-01 and all three plans. The US node is ineligible for selection. Q-04 specifies its outline. |
| Q-03 | closed | On November 22 the user chose to publish the plan for review first. | Planning review was published first. The owner authorized execution on November 24. |
| Q-04 | closed | On November 24 the user requested one outline policy for all countries. The plan adopts outlines for all to support Canada-only GPS tracking and explicit US geometry lookup. | R-01, R-04, R-05 and Plans 01–03 separate outline availability from tracking eligibility. |

## Plan review and delivery

- November 22, 2026, source revision `acdae322d`. Reviewed the whole series against the user decisions, catalog/consumer contracts, dependency order, ownership and acceptance checks. The current horizon covers plans 01 and 02. Plan 03 remains an outline until both supply its refinement evidence.
- Independent review found three cases that affect the design. Plan 01 now tests GPS confidence on both sides of a tracked child boundary. Plan 02 covers recovery after an interrupted multi-file adoption. Plan 03 protects portable backups and account data from older readers that drop unknown region IDs. Source review also identified the existing US-only picker and the distinction between uncorrected GPS and explicit history.
- The plan's repository links and three Mermaid diagrams were checked locally. Publisher checks cover the US archive, the Canadian layer inventory and a sample island geometry. Full-data conversion, simulator timing, mixed-version tests and app acceptance belong to execution.
- November 24, 2026, revision of `9422d93db`. Reviewed the country-outline rule across the four plan files. Plan 01 verifies the US node on fixtures. Plan 02 builds both outlines from the full source membership. Plan 03 adopts and credits the US node, its outline and its parent links together. Geometry access is independent of the list Where can track.
- [Planning PR #560](https://github.com/kyleve/Stuff/pull/560). [Selected Linear issue](https://linear.app/kve/issue/STU-348).
