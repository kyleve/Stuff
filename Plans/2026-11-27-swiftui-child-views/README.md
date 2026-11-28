# Apply the SwiftUI child view rule across Stuff

The audit found **194 child-helper candidates in 88 files**. Their current bodies put **124 in the 5–19-line band** and **70 in the 20+-line band**. WhereUI accounts for 150, shared packages for 40, and the intent and share extensions for four. The [source index](audit.md) gives each helper’s file, declaration line and measured size. The [whole-button inventory](buttons.md) measures controls from their initializer through the last attached modifier.

## Planning checkpoint

On November 27, 2026 the maintainer requested an audit and an implementation plan for the rule merged in [PR #576](https://github.com/kyleve/Stuff/pull/576). The November 27 revision covers every confirmed finding and measures buttons as complete controls. The maintainer reviewed the plan and authorized execution of the full series on November 27. Source evidence uses `5b1747d01`. The pilot passed four behavior tests and both snapshot suites. [PR #594](https://github.com/kyleve/Stuff/pull/594) publishes it above the [plan PR](https://github.com/kyleve/Stuff/pull/593). [STU-352](https://linear.app/kve/issue/STU-352) tracks the migration. On November 27, the review of plans 02–04 checked the pilot measurements, each succeeding slice’s source boundaries, suite names and overlapping open PRs. The first three batches are the region picker, the Year mode picker and the Installer browser. The coordinator integrates their isolated source changes into the stack, runs tests and publishes each verified slice. `next_horizon` owns the region picker, Settings, Developer and widget surfaces, `pilot_review` owns Where composition and system hosts, and `pilot_source` owns shared packages. The coordinator owns the remaining feature slices and the final inventory reconciliation.

The implementation is published in [stack #595](https://github.com/kyleve/Stuff/stack/595). Plans 01–03 have delivered their verified changes. The physical-device Siri check in plan 04 is deferred by the maintainer. The next repository maintenance action is the merged-revision guidance check below. [STU-352](https://linear.app/kve/issue/STU-352) remains In Review.

## What the audit measured

The merge introduced a rule for adding or changing a SwiftUI child view. This series applies it to existing children in tracked Swift sources, including app and extension hosts, packages, DEBUG previews, snapshots and test fixtures. For each child, count the nonblank, non-comment lines inside its formatted body, including modifiers and branches. Below five lines the rule requires no extraction. At 5–19 lines the named child belongs in the parent’s file. At 20 or more it belongs in its own Swift file. The [building-ui skill](../../.agents/skills/building-ui/SKILL.md#swiftui-view-extraction) owns the rule.

| Observed at the audited revision | How to use it |
| --- | --- |
| 1,615 tracked Swift files parsed. 208 non-body methods and properties explicitly returning `some View` reached five lines. | Eight modifier APIs, three button-style witnesses and three screen-content witnesses retain their contracts. The remaining 194 comprise 74 methods and 120 properties, including local and fixture helpers. |
| 34 already-named views have a 20+-line body in a file named for another type. | Call-site review found 27 runtime children and seven preview, capture or test renderers. Identify the component each type already represents. Move the type intact when it owns a complete control. Recount after extracting separate children from a larger composition. |
| 113 existing 5–19-line named bodies live in files matching their type names. | The [small named view index](small-named-views.md) supports a caller review. Bring a private, single-parent presentation child into its parent’s file. Identify the owning entry point for reusable components, independently presented screens and fixtures. |
| 217 explicit SwiftUI buttons, of which 97 measure 5–19 lines and 14 measure 20+ lines. | The [whole-button index](buttons.md) lists all 111 threshold hits in 72 files. Ten already form the complete rendering expression of a named view. Check their placement and reconcile overlaps with helper and builder entries. |
| 1,206 view-building closures reached five lines across 296 files. The index also identifies 335 branch expressions. | These are overlapping inspection locations. A builder can contain several siblings, setup code or a call to an existing named view. Identify a rendered child, count its complete expression including modifiers, and choose placement from its final body. |

## Choosing the child to extract

Identify the component a parent presents, then count its complete expression. For a button, include the initializer and role, action or intent, label, hit area, enabled state, styling and accessibility modifiers that belong to it. Its named view can receive an action from the parent that owns a sheet, selection or model. An existing named view that already represents the entire button is the extraction boundary. Count that view’s formatted body to choose its file.

Builder lines locate the code. A three-line label can belong to a nine-line button. Conversely, the label and its stacks inside a complete button may all appear in the inline index. Reconcile those entries against the same control. Record a separately reusable label when it has its own callers and purpose.

- `FeatureShareSheetPreview.shareSource` is exactly 20 lines. The same file contains a separate inline `Group` at line 19 that measures 37 with its frame modifier. The four-line `sourceIcon` stays below the threshold. [FeatureShareSheetPreview.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Evidence/FeatureShareSheetPreview.swift#L19)
- `RegionPickerRegionRow` already has a name. Its 39-line body contains five setup lines and the complete 34-line region-selection button. Move the existing row intact to `RegionPickerRegionRow.swift`. Keep the animated draft toggle, hit area, selection indicator, accessibility traits and disabled state together. The 23-line label is part of that move. [RegionPickerView.swift](../../Where/WhereUI/Sources/Regions/RegionPickerView.swift#L215)
- `RemovedDeviceView` has no qualifying view-returning helper. Its title-and-description stack at line 19 is an eight-line child. Its adjacent Rejoin button measures ten lines from the localized title through `.controlSize(.large)`, including the teardown action. Extract the complete button as a named child in the same file. [RemovedDeviceView.swift](../../Where/WhereUI/Sources/Devices/RemovedDeviceView.swift#L19)

The [recount recipe](recount.md) reproduces the declaration tallies. The [inline index](audit.md#inline-review-locations) records source locations for the baseline. A separate pass identified [local view bindings and 30 direct sibling expressions](audit.md#local-values-and-sibling-expressions). Syntax alone cannot establish the result type of every inferred expression, its logical parent, or its effect on SwiftUI identity. The feature passes include review of concrete return types, local view values, specialized result builders and short closures with long enclosing modifier chains.

## Stories and requirements

| ID | Outcome |
| --- | --- |
| US-01 | A maintainer can find a child by name and predict where its implementation belongs. |
| US-02 | Someone using the app, a widget, a snippet or a shared screen keeps the same interactions and presentation after extraction. |
| R-01 | Give each qualifying component a named `View`. Select the complete control before measuring. Extract the entire button with its action, label and control modifiers. Apply the two placement bands to the formatted body, including for an existing named control. Serves US-01 in plans 01–04. |
| R-02 | Preserve existing public entry points, hierarchy-sensitive modifier order, bindings, identity, environment, accessibility, navigation, side effects and cancellation. Use existing state and typed inputs. Serves US-02 in plans 01–04. |
| R-03 | Address every confirmed extraction or placement issue across the selected work. Keep each open until its change and verification are recorded. Reconcile overlapping anchors to the delivered component and record source evidence for sites already compliant or outside the rule. Verify affected surfaces through their owning tests and hosts. Serves both stories in plans 01–04. |
| X-01 | Product changes, public API redesign, state-model migrations and snapshot rebaselining for unintended differences are outside this migration. |
| X-02 | A permanent lint rule, CI gate and repository-wide formatter changes are outside scope. |

## Execution order

| Plan | Status | Deliverable |
| --- | --- | --- |
| [01 · InstallerKitUI pilot](01-installer-pilot.md) | Complete | Cover two source files with examples on both sides of the threshold. Verify the public update screen and build-detail rendering. |
| [02 · Shared modules](02-shared-modules.md) | Complete | Finish the shared packages by owning module, including view tools, catalogs and test or preview fixtures. |
| [03 · WhereUI features](03-where-features.md) | Complete | Work through feature-owned leaves, galleries, editors, Settings, Developer and shared presentation, with their tests and fixtures. |
| [04 · Where composition and hosts](04-where-composition.md) | Blocked | Cover stateful screens, calendar and tab composition, launch, onboarding and app or extension hosts. |

The pilot supplies measured placement examples and a checked way to preserve state. Plans 02–04 can then proceed in independent, reviewable module or screen batches. Assign a test helper used by several features to the batch that owns its rendered subject and record the reference from any other consumer. For each batch, compare with the implementation base, record concrete child sizes and dispositions, and preserve existing tests and snapshot references.

## After the implementation stack merges

1. Rescan tracked Swift on the merged revision, including files added since the baseline. Reconcile each confirmed finding with its verified correction and each remaining review site with its disposition.
2. Compare the stack’s review findings and verified fixes with the guidance agents read. Ensure the [building-ui extraction rule](../../.agents/skills/building-ui/SKILL.md#swiftui-view-extraction) tells agents to measure the complete button with its action, label and control modifiers, and to move an existing named control intact when its body warrants a separate file. Add any missing instruction and link a merged example.
3. Use the [review-lessons criteria](../../.agents/skills/review-lessons/SKILL.md#correct-the-owner) for any other corrections. Put a verified module-specific exception in its nearest applicable `AGENTS.md`. Keep the shared extraction rule in `building-ui`. Follow the [guidance validation steps](../../.agents/skills/normalize-agent-guidance/SKILL.md#verify-and-deliver), including `./sync-agents --check` and validation of any edited skill. Record the merged example, guidance PR or existing coverage, and checks here before closing the series.

## Questions and review

**Q-01 · closed.** Does a long scope, such as a view body, toolbar builder or drawing callback, count as a child by itself? The merged wording and source roles identify the rendered child as the unit. Inspect the hosted visuals while preserving framework witnesses, typed builders and callbacks. Incorporated into R-01, R-03 and the index on November 27.

**Q-02 · closed.** How should overlapping candidates determine final file placement? The initial plan measured nested expressions first. On November 27 the maintainer clarified that the extraction unit for a button is the whole control. Select that boundary first, then measure its formatted body and remeasure an enclosing composition after the move. R-01, the region-picker example, the pilot and the whole-button inventory incorporate the correction. The maintainer also requested coverage of every finding, now explicit in R-03.

The November 27 plan review checked the rule against its merge, source declarations against the two thresholds, and representative inline and named sites against their callers. The review removed protocol and modifier declarations from the helper tally, identified preview or test renderers among named bodies, and added a caller review for small views already in separate files. It traced each area to an owning deliverable and inspected the pilot’s proposed checks against actual hosted and snapshot suites. SwiftFormat lint passed on the audited tree. After [PR #592](https://github.com/kyleve/Stuff/pull/592) merged, the full scan at `5b1747d01` matched the declaration and builder totals at `51d7cbfbf`. The inline index uses the newer revision. For the whole-button revision, the review compared the independent control count with the source and checked the named region row, the inline Other Builds button and the intent-backed snippet. The diagram and Swift sketch describe proposed ownership. This static audit provides no runtime or image evidence for future extractions.

## Implementation audit

The final source revision is `bdbf07075`. The three original indexes refer to the Swift sources at `5b1747d01`. They contain 320 distinct paths. The shared-package review covered 81, the Settings, Developer, widget-rendering and snippet review covered 116, and the Where composition, extension and feature-flow review covered 83. The remaining 40 belong to Regions, Resolution, shared presentation, device recovery and their fixtures. The numbered plans group delivered components and retained framework, screen and fixture boundaries by owner. A path can contain several overlapping helper, label, control and modifier anchors.

| Check | Baseline | Implementation |
| --- | ---: | ---: |
| Tracked Swift files | 1,615 | 1,687 |
| Qualifying view-returning helpers | 194 | 0 |
| Named bodies of 20+ lines flagged for file placement | 34 | 0 |
| Framework or modifier boundaries retained by the recount | 14 | 14 |
| Complete button expressions of 5+ lines | 111 | 90 |

The final broad verification ran 429 behavior tests and 53 snapshot tests. The targeted reruns also covered the Inspector and Periscope interactions, the evidence gallery, the export fixture and 10 grid-pixel and reference-image checks. All passed with the baseline images in place.

The button count measures initializer expressions at the implementation site. Several callers now use one shared control. All except four expressions are direct roots of named button views. Two are the mutually exclusive modes of InspectorLaunchButton. DeveloperCrashButton and DiagnosticPersonalDataToggle contain the other two inside native confirmation-dialog action builders. Their destructive roles and presentation remain attached to the original controls.

The recount also reports 117 small views with a matching filename. These include public or navigable screens, independent snapshot or export roots and controls shared by several parents. The owner reviews and named placements in plans 02–04 distinguish those cases.

### Native host results

- Photos opened Where’s share sheet with a synthetic screenshot. Cancel returned to the share sheet. Save returned to Photos and wrote one byte-for-byte matching image to the isolated app-group store.
- WidgetKit displayed Today small and Day Counts small and medium in the gallery. The medium Day Counts widget also rendered its live empty state on the Home Screen.
- Inspector selected a row, cancelled its native deletion confirmation, returned to its table and loaded the next page. Periscope opened both Spans destinations, returned to Logs, filtered, searched and exported its seeded record.
- The Privacy prompt exposed Cancel and the destructive action. Native cancellation preserved revision 2 and all three policy copies. Activating the destructive action in a fresh in-memory fixture advanced it to revision 3.
- Broadway Catalog launched on the simulator and RegionViewer built for Mac Catalyst. The physical-device Siri or Shortcuts invocation remains pending at the maintainer’s request.

After maintainer review and merge, run the recount on the merged source, update the agent guidance against the verified examples, and close STU-352 when the acceptance record is complete.

### Verification

The implementation passed the repository formatter and architecture checks. Owning behavior, accessibility and snapshot results are recorded with their feature batches. The snapshot runs used the original reference images with recording disabled. The full declaration recount covered all tracked Swift files at the implementation revision above.
