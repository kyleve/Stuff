# US and Canadian regions in Where

Where supports Canada's ten provinces and three territories and the existing 50 US states, Washington, DC, and Puerto Rico. Each subdivision identifies its country through its parent ID. Both countries serve as catalog parents. A maintainer can refresh the boundaries from their publishers for use offline.

## Planning checkpoint

- **Operation.** On November 25 the owner approved applying the US tracking algorithm and its 25 m displacement cap to Canada and future publisher sources (Q-08). The implementation owner completed [plan 07](07-tracking-accuracy.md) on `codex/north-american-regions` for [STU-348](https://linear.app/kve/issue/STU-348) and [PR #563](https://github.com/kyleve/Stuff/pull/563).
- **Current horizon.** Plans 01–07 are complete on the implementation branch. [Plan 06](06-tracking-and-display-boundaries.md#execution-evidence) delivered separate tracking and display boundaries. The shared tracking verifier now covers the US and Canadian releases. [Plan 07’s verification](07-tracking-accuracy.md#execution-evidence) records the full-precision results, reproducible bundle and simulator checks.
- **Earlier delivery.** The November 18 research covered the US, Canada and EU. The November 22 request selected North America and plan publication. [Planning PR #560](https://github.com/kyleve/Stuff/pull/560) recorded the November 24 decision to store both country outlines. Plans [01](01-region-hierarchy.md), [02](02-boundary-updater.md) and [03](03-ship-regions.md) were verified on PR #563 in `522a032df`, `0cb45316f`, `a6e0bea86` and `c94ce9640`. Their 68-file release, 1,754 executed unit tests and 438 image references across 27 suites are the baseline for this revision.

## User stories

| ID | Outcome |
| --- | --- |
| S-01 | A traveler can select Ontario and Quebec separately. A Toronto GPS fix credits Ontario when tracked. Unselected provinces can be identified from saved coordinates in Elsewhere. |
| S-02 | A RegionKit consumer can look up the country of California or Nunavut and enumerate the subdivisions of either country from metadata. |
| S-03 | A maintainer can reproduce the checked-in catalog or evaluate a new publisher release, see what changed and retry a failed refresh safely. The installed app works offline. |
| S-04 | Someone taking a ferry can receive credit for the tracked state or province whose published boundary contains their GPS fix. The same traveler sees Long Island’s shoreline in cards and on maps. |

## Requirements

| ID | Required behavior | Story | Deliverable |
| --- | --- | --- | --- |
| R-01 | Resolve each subdivision’s country from its parent ID and enumerate the parent’s direct children. The US has 52 catalog children and Canada has 13. Both countries are metadata-only. | S-02 | [05](05-country-parents.md) |
| R-02 | Attribute each fix to one tracked region with caller priority for overlaps. Use the resulting boundary for live confidence. Offer the supported subdivisions in the existing flat workflows. | S-01, S-02 | [05](05-country-parents.md) |
| R-03 | Provide one documented, version-aware maintainer entry point with deterministic generation, cached/offline replay, explicit upstream refresh and failure recovery. | S-03 | [02](02-boundary-updater.md), [04](04-country-geometry.md) |
| R-04 | Use official WGS84-transformed boundary data, stable source-to-app ID mapping, traceable licences and reproducible inputs. Validate geographic detail, size and runtime cost before bundling. | S-01, S-03 | [02](02-boundary-updater.md), [03](03-ship-regions.md), [04](04-country-geometry.md) |
| R-05 | Offer 66 file-backed regions and retain the separate Other sentinel. Country relationships come from subdivision metadata. Credit each bundled geometry. | S-01, S-02, S-03 | [05](05-country-parents.md) |
| R-06 | Carry a tracking boundary and a display boundary for each North American subdivision. Use tracking for coordinate attribution, distances and confidence. Draw the shoreline in the app and use its polygons for picker taps. | S-01, S-04 | [06](06-tracking-and-display-boundaries.md) |
| R-07 | Match each product to stable region IDs, credit it by use and reproduce the entire paired release offline. Select display detail for the sizes Where renders. | S-03, S-04 | [06](06-tracking-and-display-boundaries.md) |
| R-08 | Keep each generated tracking boundary within 25 m of the original publisher geometry in both directions. Restore source vertices where needed, preserve shared edges and certify each encoded file on every release. Apply the same rule when adding a tracking source. | S-01, S-03 | [06 for TIGER](06-tracking-and-display-boundaries.md#us-tracking-accuracy), [07 for all generated sources](07-tracking-accuracy.md) |

## Scope boundaries

| ID | Boundary |
| --- | --- |
| X-01 | Preserve existing EU bloc behavior and geometry. Keep US tracking limited to the current 52 jurisdictions. The four additional Census records (AS, GU, MP and VI) stay outside the app catalog. Other remains the sentinel. |
| X-02 | Keep existing lists, search, maps and manual entry. Hierarchical browsing, breadcrumbs and parent/child labels are excluded. |
| X-03 | A single GPS fix earns one region. This work excludes automatic ancestor day totals, assigning subdivisions to historic manual entries or corrections, and rewriting raw observations. Existing read-time GPS attribution still uses the current tracked set and geometry. |
| X-04 | Source downloads happen on a maintainer's machine. Runtime downloads, location lookups against a server and scheduled update jobs are outside scope. |
| X-05 | The display product is a generalized shoreline. Survey-grade coastlines, an exact mask of every inland waterway and inferred ownership of water outside the tracking sources are outside scope. |

## Findings at the start of planning

- The original catalog contained 54 geometry files totaling 2,156,498 bytes. The default attributor loaded four regions. The decoder discarded interior rings. The live resolver used distance to the boundary when testing GPS accuracy. [RegionKit](../../Where/RegionKit/README.md), [GeoJSON reader](../../Where/RegionKit/Sources/GeoJSON.swift), [live resolver](../../Where/WhereCore/Sources/Location/CurrentRegionResolver.swift)
- RegionKit's public raw-value initializer validates input. Its Codable representation is a bare string. Some store and forecasting reads still validate against the installed catalog, so an older build can discard a newly introduced ID even though the wire shape is identical. Plan 03 addresses mixed-version access before the first new ID is written. [Region](../../Where/RegionKit/Sources/Region.swift), [store](../../Where/WhereCore/Sources/Persistence/SwiftDataStore.swift), [account compatibility version](../../Where/WhereCore/Sources/Compatibility/DataModelVersion.swift)
- The original primary picker filtered IDs by `us-`. The Settings editor could drop a saved Canada selection, and forecasting used the same US list. Plan 03 supplied flat US and Canadian choices to these workflows. [Primary picker](../../Where/WhereUI/Sources/Regions/PrimaryRegionSelectionModel.swift), [forecast picker](../../Where/WhereUI/Sources/Forecasting/PlanningRegionSelectionModel.swift)
- US Census publishes a versioned national state/equivalent ZIP. Use its 2026 TIGER/Line release and postal codes to carry existing IDs forward. StatCan's 2026 detailed cartographic layer supplies land and coastal islands, English and French names, and all 13 PRUIDs. Map those IDs explicitly to `ca-ON`, `ca-NT`, etc. Its service assigns the Open Government Licence – Canada. These are the selected sources from the research. The Canadian choice follows the land-based logging recommendation. Boats in coastal waters can fall outside that layer. [US archive](https://www2.census.gov/geo/tiger/TIGER2026/STATE/), [Canadian product definitions](https://www150.statcan.gc.ca/n1/daily-quotidien/261118/dq261118f-eng.htm), [province and territory layer](https://geo.statcan.gc.ca/geo_wa/rest/services/2026/Cartographic_boundary_files/MapServer/0), [licence](https://open.canada.ca/en/open-government-licence-canada/)
- The selected Census source contains 56 state and equivalent records, including American Samoa, Guam, the Northern Mariana Islands and the US Virgin Islands. Only the existing 52 US jurisdictions become catalog children. The US Minor Outlying Islands are outside this source's coverage. [Census geographic coverage](https://www2.census.gov/geo/pdfs/maps-data/data/tiger/tgrshp2026/TGRSHP2025_TechDoc_Ch2.pdf)
- Plan 04 originally treated Canada as both a tracking choice and a parent. [Plan 05](05-country-parents.md) supersedes that behavior.
- November 25 follow-up. The point north of Port Jefferson is inside New York in both the raw 2026 TIGER file and the PR’s bundled polygon. The previous 2010 artwork and the 2025 Census cartographic file both exclude it. A point in the Strait of Georgia similarly distinguishes the two 2026 Canadian services. Q-06 replaces land-based Canadian logging in the original source selection. [Snapshot discussion](https://github.com/kyleve/Stuff/pull/563#discussion_r4700250594) · [Sources and sample coordinates](06-tracking-and-display-boundaries.md#boundary-products)

## Execution order and planning horizon

| Order | Plan | Outcome |
| --- | --- | --- |
| 1 | [Catalog relationships and attribution](01-region-hierarchy.md) | Completed November 24. Fixtures demonstrated parent links, stored country outlines and single-region lookup. The existing production IDs retain their order. |
| 2 | [Reusable boundary updater](02-boundary-updater.md) | A maintainer can produce a verified candidate from official vintages, without activating new app regions. |
| 3 | [Ship and verify the catalog](03-ship-regions.md) | The app consumes the approved resources, credits their sources and supports the new regions in its existing workflows. |
| 4 | [Derive country behavior from subdivisions](04-country-geometry.md) | Replace both stored country files while retaining the existing regional and country-level workflows. |
| 5 | [Countries as catalog parents](05-country-parents.md) | Retire standalone country tracking and simplify attribution to file-backed regions. |
| 6 | [Tracking and display boundaries](06-tracking-and-display-boundaries.md) | Use administrative boundaries for GPS and cartographic shorelines for drawing and picker interaction. |
| 7 | [Tracking accuracy across sources](07-tracking-accuracy.md) | Apply the same 25 m cap and selective vertex restoration to every generated tracking source. |

The first two deliverables supplied the fixture results and repeatable source release used to qualify the third. Plan 03 records the accepted simplification settings, file sizes, topology checks and measured lookup costs.

## Questions and resolutions

| ID | Status | Resolution and source | Impact and integration |
| --- | --- | --- | --- |
| Q-01 | closed | On November 22 the user chose the most specific tracked region. A Toronto fix earns Ontario alone if Ontario and Canada are tracked. | Plans 01/03 originally supported tracking Canada. Q-05 retires standalone Canada tracking and supersedes this example. |
| Q-02 | closed | On November 22 the user chose an internal United States parent and the current set of US tracking choices. | Integrated in R-01, R-05, X-01 and all three plans. The US node is ineligible for selection. Q-04 records the change to metadata-only US behavior. |
| Q-03 | closed | On November 22 the user chose to publish the plan for review first. | Planning review was published first. The owner authorized execution on November 24. |
| Q-04 | closed | On November 24 the owner required consistent country handling. The first delivery stored both outlines. On November 25 the owner withdrew that choice because the separate geometry is redundant. | [04](04-country-geometry.md) replaces the former design in R-01, R-04 and R-05. Country relationships come from child metadata. At that revision the US was internal and Canada remained selectable. Q-05 supersedes its tracking eligibility. |
| Q-05 | closed | November 25. The owner approved deriving countries from subdivisions. No country-specific manual entries, home, stays or explicit corrections need to be retained. | Plan 05 supersedes the Canada tracking assumptions in Q-01 and Q-04. Existing GPS coordinates still support Elsewhere enrichment. |
| Q-06 | closed | On November 25 the owner selected administrative boundaries for tracking and accepted simplified land boundaries for rendering after reviewing the Long Island snapshots. The verified Canadian pair was part of the same recommendation. | Integrated into S-04, R-06, R-07, X-05 and [plan 06](06-tracking-and-display-boundaries.md). The picker keeps its existing convention of selecting the shape it draws. [Card](https://github.com/kyleve/Stuff/pull/563#discussion_r4700193764) · [Full map](https://github.com/kyleve/Stuff/pull/563#discussion_r4700250594) |
| Q-07 | closed | November 25. The owner initially selected 50 m for US tracking, requested a comparison, then chose 25 m with the same local edge restoration. | R-08 and [plan 06](06-tracking-and-display-boundaries.md#us-tracking-accuracy) replace the earlier instruction to retain the existing US tracking bytes. The 25 m run supplies feasibility evidence for the selected cap. |
| Q-08 | closed | November 25. After comparing the same restoration algorithm on Canadian digital boundaries, the owner selected it for Canada and future sources. | [Plan 07](07-tracking-accuracy.md) extends R-08 to each publisher-backed tracking release, including proof against the original Canadian input. |

## Plan review and delivery

- November 22, 2026, `acdae322d`. Review identified tracked-child accuracy on both sides of a border, interrupted adoption, and compatibility for older backup and account readers. Plans 01 and 02 supplied the fixture and release evidence used to refine 03. [Planning PR #560](https://github.com/kyleve/Stuff/pull/560)
- November 24, 2026. The owner requested a consistent country-outline policy. The original execution produced national files from the full source memberships. The three completed plans preserve that decision, implementation, measurements and checks. [Original review comment](https://github.com/kyleve/Stuff/pull/560#discussion_r4685927230)
- November 25, 2026, starting at `c94ce9640`. Reviewed the revised data flow and inventory against the current consumers, the stable IDs and Q-01 through Q-04. All four Mermaid diagrams rendered and all local plan targets resolved. The direct request replaces the previous US outline lookup and both national resources. [Plan 04](04-country-geometry.md) owns the repeat verification for country confidence, drawings, physical resources and update replay.
- November 25, 2026, starting at `ab28552e5`. [Plan 05](05-country-parents.md) retired standalone country tracking, kept the 66 boundary files intact and verified subdivision attribution, picker behavior, Spotlight cleanup and the embedded app and extension resources. All five iOS test bundles and the full WhereUI snapshot suite passed. [Implementation PR #563](https://github.com/kyleve/Stuff/pull/563)
- November 25, 2026, `6425c8ec6`. Reviewed the scope of plans 01–06 and traced the follow-up from both updater adapters through tracking, artwork, map taps, diagnostics and source credits. Independent review identified duplicate batch requests that could collide on outline IDs, the undated EU source and the per-region credit rule. Plan 06 incorporates all three. All six Mermaid diagrams rendered and local links and anchors resolved. These are design checks. Implementation, bundle measurements and visual acceptance remain pending.
- November 25, 2026, `5a6d137e8`. Reviewed R-08 against the updater and both US tracking prototypes. Independent verification checked the decoded files against the entire original boundary in both directions for all 52 jurisdictions. Plan 06 records the 50 m decision, the 25 m comparison, and how offline adoption verifies the displacement report belongs to the exact bundle. All six diagrams rendered. Production adoption remains pending.
- November 25, 2026, `f69ad364d`. After reviewing the measured accuracy and cost, the owner chose 25 m for US tracking. Reviewed the source selection, restoration settings, diagram and release acceptance criterion against the verified 25 m candidate. Production adoption remains pending.
- November 25, 2026, starting at `03b6c5bca`. [Plan 06](06-tracking-and-display-boundaries.md#execution-evidence) shipped paired tracking and display products on PR #563. The complete TIGER tracking boundary stayed within 24.00 m of the source. That release retained Canadian tracking at publisher resolution. Its 45 m display geometry preserved Maritime tidal channels lost by the 180 m trial. All five iOS unit bundles and the full WhereUI snapshot suite passed.
- November 25, 2026, starting at `7a63c76a2`. Reviewed [plan 07](07-tracking-accuracy.md) against the Canadian prototype, the US release verifier and offline adoption. The prototype compared against already repaired Canadian geometry. Production acceptance requires original publisher input and the final decoded tracking files.
- November 25, 2026. The format-4 release certified all 65 publisher-backed tracking files. The verified upper bounds were 24.008 m for Canada and 24.000 m for the US. Canadian tracking uses 357,139 bytes. [Release checks and review handoff](07-tracking-accuracy.md#execution-evidence)
