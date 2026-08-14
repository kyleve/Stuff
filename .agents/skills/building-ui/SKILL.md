---
name: building-ui
description: Build and review this repository SwiftUI and UIKit surfaces. Use its layering, reuse, Broadway design-system, layout, accessibility, localization, preview, and image-snapshot conventions. Use when you create or change a view, screen, component, widget, app-extension UI, stylesheet, visual token, animation, UIKit bridge, preview, SnapshotProviding matrix, or UI snapshot reference. Use when you review UI code or rendered output.
---

# Building UI

Build repository UI through the existing model, design-system, and rendering
seams. Treat this skill as the repository-specific authority when generic
SwiftUI guidance conflicts with it. For example, use a Broadway stylesheet,
not a generic constants enum. Use `swiftui-pro` alongside this skill for
current SwiftUI API, performance, and platform guidance.

## Start from the existing shape

1. Read the root [`AGENTS.md`](../../../AGENTS.md), then every `AGENTS.md` that
   scopes the files being changed. Local files retain module-specific product,
   dependency, and lifetime invariants.
2. Inspect the feature's existing views, view models, reusable components,
   Broadway root, stylesheet, preview fixtures, and snapshot declarations
   before designing another path.
3. Extend an existing view with a mode or shared subview when two surfaces
   express the same concept. Keep screen-specific registration and rendering
   declarations beside the represented screen.
4. Identify the narrowest layer that owns the behavior before editing UI.

## Keep views presentational

- Put persistence, domain rules, detection, aggregation, cache policy, and side
  effects in Core/services. Put observable mirrors, lifecycle orchestration,
  and intent methods in a view model. Let a `View` render state and route
  intents.
- Extract an `@Observable` model or focused child type when a view begins to
  own system logic, an internal state machine, or unrelated behavioral areas.
- Model mutually dependent UI values as one enum or named value so invalid
  combinations cannot be represented.
- Bind directly to observable state. For a derived binding, expose a computed
  get/set property on the model and bind to it. Do not build
  `Binding(get:set:)` in a view.
- Keep previews and tests on the production data flow. Inject a protocol fake
  or production-shaped fixture instead of adding DEBUG state or a parallel
  refresh path to product code.
- Scope presentation-driven work to actual visibility. Key tasks by every
  identity-relevant input and let cancellation return before changing durable
  presentation state, emitting haptics, or publishing late UI updates.

## Build appearance through Broadway

Before adding dependencies, read the root static-linking tripwire. If a
consumer already receives Broadway through another product, use that product's
exported root seam and do not link `BroadwayCore` or `BroadwayUI` again.

For a module that owns a design language:

1. Define one `BStylesheet` with a deterministic `static let default` for
   off-tree layout helpers, tests, and rootless fallbacks.
2. Resolve the active sheet from `bContext` through a typed
   `EnvironmentValues` property. Views read it with `@Environment`.
3. Seed `broadwayRoot(themes:)` at the composition root. Export a module root
   helper when downstream targets must seed the same context without importing
   Broadway directly. A self-contained public tool can seed its own root so it
   renders correctly inside or outside a host app.
4. Keep fixed values in property defaults or `standard` values. Derive only the
   trait-reactive slice in `init(context:)`, starting from those defaults.
5. Test default values, trait derivation, environment resolution, and every
   exported root path.

Organize tokens by ownership:

- Put geometry, fonts, colors, shadows, motion, and other authored appearance
  on the owning component's nested style struct. Nest subparts when a group
  grows. Do not grow a flat stylesheet or flat component style.
- Use shared spacing, size, palette, typography, or motion scales only when a
  token is genuinely cross-component. Do not borrow another component's style.
- Model a visual axis as a typed `Variant` and resolve one complete style with a
  subscript or resolver before rendering. Avoid scattering conditional token
  reads through `body`.
- Give a reusable rendering primitive an appearance/style input. Let the
  parent component's style own product meanings such as watermark or stamp.
- Keep live-container, content, or measured-chrome geometry in the layout/view
  layer. A stylesheet cannot resolve a value that exists only after layout.
- Leave adaptive system roles such as `.secondary` and `.accentColor` inline
  when they are semantic rather than authored design tokens.

Derive coordinated accessibility changes in the stylesheet through
`SlicingContext.traits`: content-size category, Reduce Motion, Reduce
Transparency, and Differentiate Without Color. Vend one resolved component
style when a setting changes several values together. Keep an explicit helper
only when the result cannot be an `Equatable` token, such as a transition or a
capture-time static motion phase.

See the WhereUI [design-system guide](../../../Where/WhereUI/README.md#design-system)
for the fullest production example and PeriscopeTools/Flyover for smaller
module-owned stylesheets.

## Make layout adaptive

- Prefer semantic system APIs such as `defaultScrollAnchor`,
  `containerRelativeFrame`, safe-area APIs, and adaptive stacks before reaching
  for `GeometryReader`.
- When real chrome must be measured, use a focused preference or
  `onGeometryChange`. Compute expensive layout once into state rather than on
  every `body` pass.
- Use semantic fonts and scale authored dimensions with `@ScaledMetric` when
  the whole element must grow. If a glyph sits inside a fixed
  container, give it an intentional fixed font. If its text scales, grow or
  restack the surrounding layout rather than truncate or squeeze it.
- Preserve navigation bars, toolbars, search, safe-area insets, and modal chrome
  when introducing custom containers or scroll behavior.
- Animate insertion/removal with a transition on each state branch plus an
  animation keyed to the state. Pair each `contentTransition` with an animation
  keyed to the displayed value. Hidden content must leave the tree rather
  than remain at zero opacity.
- Keep the visual structure consistent across states and variants unless the
  difference is intentional and modeled by the component style.

## Build for accessibility and localization

- Exercise standard and accessibility Dynamic Type while constructing the
  layout. Restack crowded rows, grow meaningful accents and tap targets, and
  keep complete labels and values readable.
- Give custom full-screen modal surfaces the `.isModal` accessibility trait and
  post `.screenChanged` when crossing the modal boundary.
- Never rely on color alone when Broadway reports Differentiate Without Color.
- Resolve user-facing copy through the owning module's generated
  `LocalizedStringResource` symbols. Keep DEBUG UI localized unless its module
  explicitly documents developer-only literal strings.
- Format numbers, dates, and measurements with `FormatStyle` or the module's
  shared formatter rather than interpolation or ad-hoc strings.

## Keep UIKit bridges focused

- For one full-bleed child view controller, complete containment normally and
  set `child.view.frame = view.bounds` in `viewWillLayoutSubviews`. Do not add
  four edge constraints.
- Observe with target/selector and remove by observer identity. Pair every
  `start`-style observation API with `stop`, and remove before re-adding on a
  restart.
- Hide a necessary UIKit workaround behind one focused adapter so SwiftUI views
  keep typed presentation state and do not repeat controller plumbing.

## Author previews and image coverage with the view

- Put at least one `#Preview` in the represented view's source file under
  `#if DEBUG`. Use synchronous, in-memory, production-shaped fixtures. Cover
  empty, loaded, failure, and distinct edge states that matter.
- When a module uses SnapshotKit, put its `SnapshotProviding` conformance in the
  same source file and render `Self.snapshotPreviews` from the preview. Declare
  the matrix once and use one `FooSnapshotTests` suite/file per represented
  view.
- Snapshot the production branch. Use a stand-in only for externally loaded or
  wall-clock-dependent content that no settle window can stabilize, keep its
  layout identical, and encapsulate the substitution inside the shared
  component rather than branching at every call site.
- Centralize never-settling motion behind the module's static-motion helper.
  Do not scatter `isCapturingSnapshot` checks through product views.
- Keep generic capture mechanics in SnapshotKit/SnapshotKitTesting and
  consumer-specific root wrapping in the UI module.
- For intrinsic/full-content cases whose fixture has a synchronous final
  height, set `measurementReadiness: .immediate` to avoid paying a redundant
  sizing settle. Keep `.sameAsCapture` when async work can change height, and
  never weaken the case's final `settle` to optimize measurement.
- Review every changed reference for content, navigation/tool/search chrome,
  background, safe areas, Dynamic Type, and accessibility annotations. Give a
  chrome-free capture an explicit production background instead
  of inheriting a transparent test host. A blank, clipped, incomplete, or
  visibly broken image is a product or capture defect. Fix it before recording
  a reference.

Use the [`running-tests`](../running-tests/SKILL.md) skill to select and run the
affected unit and image suites. A view or appearance change normally requires
snapshot validation even when its unit tests pass.
