# Apply the SwiftUI child view rule across Stuff

The audit found **194 child-helper candidates in 88 files**. Their current bodies put **124 in the 5–19-line band** and **70 in the 20+-line band**. WhereUI accounts for 150, shared packages for 40, and the intent and share extensions for four. The [source index](audit.md) gives each helper’s file, declaration line and measured size. It also lists inline builder locations and existing named children.

## Planning checkpoint

On November 27, 2026 the maintainer requested an audit and an implementation plan for the rule merged in [PR #576](https://github.com/kyleve/Stuff/pull/576). Discovery and plan review are complete at `5b1747d01`. The [InstallerKitUI pilot](01-installer-pilot.md) is ready. The other three deliverables are outlines with refinement triggers. [STU-352](https://linear.app/kve/issue/STU-352) tracks the migration. Execution awaits a separate request.

## What the audit measured

The merge introduced a rule for adding or changing a SwiftUI child view. This series applies it to existing children in tracked Swift sources, including app and extension hosts, packages, DEBUG previews, snapshots and test fixtures. For each child, count the nonblank, non-comment lines inside its formatted body, including modifiers and branches. Below five lines the rule requires no extraction. At 5–19 lines the named child belongs in the parent’s file. At 20 or more it belongs in its own Swift file. The [building-ui skill](../../.agents/skills/building-ui/SKILL.md#swiftui-view-extraction) owns the rule.

| Observed at the audited revision | How to use it |
| --- | --- |
| 1,615 tracked Swift files parsed. 208 non-body methods and properties explicitly returning `some View` reached five lines. | Eight modifier APIs, three button-style witnesses and three screen-content witnesses retain their contracts. The remaining 194 comprise 74 methods and 120 properties, including local and fixture helpers. |
| 34 already-named views have a 20+-line body in a file named for another type. | Call-site review found 27 runtime children and seven preview, capture or test renderers. Process their inner children and remeasure before moving a type. |
| 113 existing 5–19-line named bodies live in files matching their type names. | The [small named view index](small-named-views.md) supports a caller review. Bring a private, single-parent presentation child into its parent’s file. Identify the owning entry point for reusable components, independently presented screens and fixtures. |
| 1,206 view-building closures reached five lines across 296 files. The index also identifies 335 branch expressions. | These are overlapping inspection locations. A builder can contain several siblings, setup code or a call to an existing named view. Identify a rendered child, count its complete expression including modifiers, and choose placement from its final body. |

Three examples show where the distinction matters.

- `FeatureShareSheetPreview.shareSource` is exactly 20 lines. The same file contains a separate inline `Group` at line 19 that measures 37 with its frame modifier. The four-line `sourceIcon` stays below the threshold. [FeatureShareSheetPreview.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Evidence/FeatureShareSheetPreview.swift#L19)
- `RegionPickerRegionRow` already has a name. Its 39-line body includes a 23-line button label. Extract the label first, format the call that replaces it, then remeasure the row. [RegionPickerView.swift](../../Where/WhereUI/Sources/Regions/RegionPickerView.swift#L215)
- `RemovedDeviceView` has no qualifying view-returning helper. Its title-and-description stack at line 19 is an eight-line child. The adjacent button action runs a teardown task. [RemovedDeviceView.swift](../../Where/WhereUI/Sources/Devices/RemovedDeviceView.swift#L19)

The [recount recipe](recount.md) reproduces the declaration tallies. The [inline index](audit.md#inline-review-locations) records source locations for the baseline. A separate pass identified [local view bindings and 30 direct sibling expressions](audit.md#local-values-and-sibling-expressions). Syntax alone cannot establish the result type of every inferred expression, its logical parent, or its effect on SwiftUI identity. The feature passes include review of concrete return types, local view values, specialized result builders and short closures with long enclosing modifier chains.

## Stories and requirements

| ID | Outcome |
| --- | --- |
| US-01 | A maintainer can find a child by name and predict where its implementation belongs. |
| US-02 | Someone using the app, a widget, a snippet or a shared screen keeps the same interactions and presentation after extraction. |
| R-01 | Give each qualifying child a named `View`. Measure from the innermost meaningful child out and apply the two file-placement bands to the formatted result. Serves US-01 in plans 01–04. |
| R-02 | Preserve existing public entry points, hierarchy-sensitive modifier order, bindings, identity, environment, accessibility, navigation, side effects and cancellation. Use existing state and typed inputs. Serves US-02 in plans 01–04. |
| R-03 | Reconcile the indexed sites and newly discovered children in each batch. Record resulting placement, overlap with a completed child, existing named implementation, or a specific reason the site represents a different contract. Verify the affected surfaces through their owning tests and hosts. Serves both stories in plans 01–04. |
| X-01 | Product changes, public API redesign, state-model migrations and snapshot rebaselining for unintended differences are outside this migration. |
| X-02 | A permanent lint rule, CI gate and repository-wide formatter changes are outside scope. |

## Execution order

| Plan | Status | Deliverable |
| --- | --- | --- |
| [01 · InstallerKitUI pilot](01-installer-pilot.md) | Ready | Cover two source files with examples on both sides of the threshold. Verify the public update screen and build-detail rendering. |
| [02 · Shared modules](02-shared-modules.md) | Outline | Finish the shared packages by owning module, including view tools, catalogs and test or preview fixtures. |
| [03 · WhereUI features](03-where-features.md) | Outline | Work through feature-owned leaves, galleries, editors, Settings, Developer and shared presentation, with their tests and fixtures. |
| [04 · Where composition and hosts](04-where-composition.md) | Outline | Cover stateful screens, calendar and tab composition, launch, onboarding and app or extension hosts. |

The pilot supplies measured placement examples and a checked way to preserve state. Plans 02–04 can then proceed in independent, reviewable module or screen batches. Assign a test helper used by several features to the batch that owns its rendered subject and record the reference from any other consumer. For each batch, compare with the implementation base, record concrete child sizes and dispositions, and preserve existing tests and snapshot references. At series closeout, rescan tracked Swift, inspect new or moved files since the baseline, and reconcile both the declaration results and inline review locations. Judge completion from the remaining declarations’ roles and the measured child bodies. Required witnesses and existing named factories can still return views.

## Questions and review

**Q-01 · closed.** Does a long scope, such as a view body, toolbar builder or drawing callback, count as a child by itself? The merged wording and source roles identify the rendered child as the unit. Inspect the hosted visuals while preserving framework witnesses, typed builders and callbacks. Incorporated into R-01, R-03 and the index on November 27.

**Q-02 · closed.** How should overlapping candidates determine final file placement? Measure the resulting formatted child after its nested extractions. The region-picker example and the pilot steps incorporate that decision. The user selected repository-wide scope. The pilot and rollout order are implementation proposals based on coverage and ownership risk.

The November 27 plan review checked the rule against its merge, source declarations against the two thresholds, and representative inline and named sites against their callers. The review removed protocol and modifier declarations from the helper tally, identified preview or test renderers among named bodies, and added a caller review for small views already in separate files. It traced each area to an owning deliverable and inspected the pilot’s proposed checks against actual hosted and snapshot suites. SwiftFormat lint passed on the audited tree. After [PR #592](https://github.com/kyleve/Stuff/pull/592) merged, the full scan at `5b1747d01` matched the declaration and builder totals at `51d7cbfbf`. The inline index uses the newer revision. The diagram and Swift sketch describe proposed ownership. This static audit provides no runtime or image evidence for future extractions.
