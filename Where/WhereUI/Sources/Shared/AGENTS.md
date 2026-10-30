# Shared presentation contracts

Read the [module contract](../../AGENTS.md) and the [repository contract](../../../../AGENTS.md) first.

- Keep render-ready region geometry in the root-injected
  `RegionOutlinePathCache`. RegionKit owns the cached source outlines and its
  stateless simplifier. WhereUI chooses full/medium/small/micro tolerances and
  caches the resulting SwiftUI `Path`s. Use the small path for the stamp. Use
  the micro path for repeated borders on location cards and estimate panels.
  Share the region artwork treatment across regular and compact cards. Keep
  compact dimensions in the compact style. Resolve Elsewhere's paper surface
  from that geometry, without a progress bar, using the shared matte renderer.
  Keep primary specimens on the selected theme's surface. Preserve Elsewhere's
  white/neutral-dark fill when Flat overrides its outline and shadow.
  Use the original region color for Elsewhere artwork and borders. Apply its
  contrast adjustment only to text.
  Project Locations-card GPS points through the cache's shared
  `RegionArtworkProjection`. Never project, simplify, or spatially reduce
  artwork in a card's `body`.
- Use `regionArtworkTask` and `RegionArtworkModel` for cached artwork loading.
  Keep request identity complete; use a broader display key only when retaining
  compatible artwork during refresh is intentional.
- Continuous/looping motion (repeat-forever pulses, `TimelineView(.animation)`,
  typewriter reveals) must consult the shared `@MotionIsStatic` helper
  ([`Sources/Shared/MotionIsStatic.swift`](MotionIsStatic.swift))
  for its static end-state. Never hand-roll the
  `\.accessibilityReduceMotion` + `\.isCapturingSnapshot` pair.
- A compact form `DatePicker` goes through `WhereDatePicker`
  ([`Sources/Shared/WhereDatePicker.swift`](WhereDatePicker.swift)).
  It substitutes a deterministic stand-in under capture. The live control
  renders relative to *today*. No reference containing one is stable across
  days. Views do not read `\.isCapturingSnapshot` to branch themselves. Capture
  handling stays inside the shared component.

## Design system — `WhereStylesheet`

Follow the repo [`building-ui`](../../../../.agents/skills/building-ui/SKILL.md)
skill for token ownership, variants, trait derivation, layout, accessibility,
and rendering coverage. Where's sheet is
[`WhereStylesheet`](WhereStylesheet.swift), read through
`@Environment(\.stylesheet)` and defaulted to `WhereStylesheet.default` off the
view tree. [`README.md`](../../README.md#design-system) documents its live API and
worked examples.

- Resolve component layout and motion in `WhereStylesheet.init(context:)`.
  Keep launch style consumers beneath `whereBroadwayRoot()`. The launch slice
  selects an `Equatable` reveal policy whose computed property builds the transition.
- Keep scoped SwiftUI appearance overrides consistent with Broadway traits.
  Pair `.dynamicTypeSize` limits with the corresponding content-size override.
  Pair explicit `.colorScheme` overrides with `.bMode` for styled subtrees.
- Keep live Card Designer and ranking-lab drafts outside the cached slice.
  These runtime inputs compose over the resolved base style. Document their
  direct system-trait reads at the declaration.
- **Per-region tints stay in `RegionStyle`.** Resolve via
  `@Environment(\.regionStyles)` and seed by
  `whereBroadwayRoot(theme:regionStyles:)`. Use no global accessor or hardcoded
  per-region look in a view.
  Derive automatic colors from the permanent region ID with a fixed hash.
  Never use localized names, card order, or Swift's randomized `Hasher`.
  Keep the catalog's palette order and hash stable across launches.
  Guard: `RegionAppearanceCatalogTests.idDerivedDefaultsHaveStableAssignments`.
- **Seed `WhereTheme` through `whereBroadwayRoot(theme:regionStyles:)`.** Standard
  and Flat use the stable `standard` and `alternate` identities.
- Bundled JSON is authoritative. Standard is a complete root; Flat inherits Standard; Halloween inherits Flat. Resolve documents through `WhereThemeCatalog` before rendering. Do not add a native theme override path.
- Keep portable appearance in `Sources/Themes/WhereThemeAppearance*`. Add each authored stylesheet field to its typed patch, inheritance, canonical Standard document, and mapping tests. Keep runtime geometry, region identity, data reduction, and lifecycle scheduling native.
- Omitted fields inherit. Explicit values replace. Artwork arrays replace as a unit, including empty arrays. Optional visuals use `WhereThemeOptional.clear`. A literal value replaces an inherited named reference; do not supply both in one document.
- Validate complete roots, parents, named references, complexity, and placement before root injection. Prepare assets once. Cache identity includes complete resolved content, not only its ID. Failed imports retain the last accepted theme.
- Apply native accessibility constraints after document resolution. Keep ornament separate from essential surfaces. Inject static-motion policy and actual host activity into Broadway's renderer.
- Use component surfaces for interior and exterior artwork. Keep paint bounds finite, reserve gaps and gutters in parent layouts, and preserve viewport clipping. Exterior artwork must not expand interaction or accessibility bounds. Keep the inner card as the zoom source.
- Validate host capabilities before injection. Keep List rows and joined timeline segments interior-only. Apply artwork spacing outside buttons and accessibility groups in other hosts. Guard: `WhereThemeComponentsCapabilitiesTests`.
- Inject `WhereThemePreviewModel` only from the Development app composition root. Scope its selected document to the ready app. Never persist preview selection or publish it to widgets or App Intents.
- **Design new and changed custom components for every supported theme.**
  Resolve theme and accessibility choices in the owning `WhereStylesheet`
  component style. Views consume that style without checking the selected theme.
  Reuse `matteSurface` for Flat's opaque fills, visible strokes, and restrained
  shadows. Keep the matte outline fully outside the clipped surface without changing
  layout or hit bounds. Use a subtle tint for pressed feedback. Exclude glass,
  reflections and luminous glows from Flat's view hierarchy. Observe tilt only while a
  visible surface needs sheen. Preserve artwork and informational gradients.
  Keep system chrome native and widget/snippet surfaces lightweight.
  Guard: `WhereStylesheetSurfaceTreatmentTests`.
- The DEBUG card designer may override only presentation values already owned
  by `CardStyles`. It must not add a second production styling system or alter
  count animation and outline-cache behavior.
- Keep the DEBUG Ranking Animation Lab session-only. It tunes the containing
  Location-card stack, never Card Designer persistence, exports, or app overrides.
- Keep the Appearance welcome reset under `#if DEBUG`. Clear only the saved welcome region through `YearReportModel.resetLocationWelcome()`.
- Keep welcome-card arrival, departure, and scrim timing in `locationWelcome.motion`. Apply spatial transitions only to the card layer.
- Keep `LocationWelcomeModel`, its overlay, and its bottom accessory owned by
  `MainTabs`. Resolve once per active-scene entry regardless of tab. Only denied
  or restricted access and disabled Precise Location stay visible as recovery
  actions; transient and confidence failures return to idle.
- Establish the first successful live-region baseline without a welcome, including after backup import.
  Preserve explicit DEBUG reset requests and commit no history from cancelled or superseded lookups. Guard: `LocationWelcomeModelTests`.

- Keep composite theme appearance groups boxed with `CopyOnWrite`. Background JSON decoding must fit a worker thread stack; preserve the unboxed JSON shape. Guard: `WhereThemeAppearanceTests`.
