# Shared presentation contracts

Read the [module contract](../../AGENTS.md) and [repository contract](../../../../AGENTS.md).

## Artwork and shared controls

- Keep render-ready paths in the root-injected `RegionOutlinePathCache`; RegionKit owns source outlines and simplification.
  Use small paths for stamps and micro paths for repeated card/estimate borders.
  Project Locations-card points through the shared `RegionArtworkProjection`, never in a card's `body`.
- Share regular/compact artwork treatment; compact dimensions belong to the compact style.
  Render Elsewhere's paper from geometry with the shared matte renderer and no progress bar.
  Keep primary specimens on the theme surface. Elsewhere keeps its white/neutral-dark fill under Flat and its original artwork/border color; contrast adjustment applies only to text.
- Load through `regionArtworkTask` and `RegionArtworkModel` with complete request identity.
  A broader display key is allowed only to retain compatible artwork during refresh.
- Continuous motion uses [`@MotionIsStatic`](MotionIsStatic.swift) for its static end state; do not duplicate the Reduce Motion/snapshot-capture checks.
- Compact form date controls use [`WhereDatePicker`](WhereDatePicker.swift).
  Its capture stand-in avoids the live control's today-relative rendering. Keep capture branches inside the shared component.

- Keep one content root per scrolling surface. Ordinary screens use `whereScreenRoot`; native forms and lists use `whereFormRoot` without another scroller.
  Reset nesting only at independent navigation or sheet destinations with `whereScreenBoundary`. Preserve inherited width and caller-owned navigation.
  Guards: `WhereScreenRootTests`, `WhereFormRootTests`, and `WhereContentRootTests`.

## Design system — `WhereStylesheet`

Use [building-ui](../../../../.agents/skills/building-ui/SKILL.md).
The [README](../../README.md#design-system) owns the stylesheet API.

- Resolve layout and motion in `WhereStylesheet.init(context:)`. Launch consumers stay beneath `whereBroadwayRoot()`, with an `Equatable` reveal policy that builds the transition.
- Pair SwiftUI Dynamic Type limits with Broadway's content-size override, and explicit color-scheme overrides with `.bMode`.
- Compose live Card Designer/ranking-lab drafts over the cached base style. Document their direct system-trait reads.
- Keep per-region tints in `RegionStyle`, injected through `whereBroadwayRoot(theme:regionStyles:)`; no global accessor or hardcoded region look.
  Automatic colors use permanent region IDs and a fixed hash, never localized names, order, or randomized `Hasher`.
  Preserve palette/hash stability. Guard: `RegionAppearanceCatalogTests.idDerivedDefaultsHaveStableAssignments`.
- Standard/Flat retain the `standard`/`alternate` identities. Standard is the base; resolve shared traits before applying theme overrides.
  Keep theme values and theme-specific trait decisions in their definition, and override application independent of selection/resolution.
  Omitted overrides inherit; explicit zero disables effects. Use `BModeVarying` for light/dark pairs and keep runtime region colors outside theme definitions.
  Guards: `WhereThemeOverridesTests`, `WhereFlatThemeTests`.
- Custom components support every theme through their owning style; views do not branch on theme.
  Reuse `matteSurface` for Flat. Keep its outline outside the clip without changing layout/hit bounds and use subtle pressed tint.
  Exclude glass, reflections, and glows from Flat's hierarchy; observe tilt only while visible sheen needs it.
  Preserve artwork/informational gradients, native system chrome, and lightweight widgets/snippets.
  Guard: `WhereStylesheetSurfaceTreatmentTests`.

## Developer and welcome behavior

- The DEBUG card designer overrides only presentation values owned by `CardStyles`; it cannot alter count animation or outline caching.
- Keep the DEBUG Ranking Animation Lab session-only and limited to the Location-card stack, separate from designer persistence, exports, and app overrides.
- The Appearance welcome reset stays DEBUG-only and clears only the saved welcome region through `YearReportModel.resetLocationWelcome()`.
- Welcome arrival/departure/scrim timing belongs to `locationWelcome.motion`; spatial transitions affect only the card layer.
- `MainTabs` owns the welcome model, overlay, and bottom accessory. Resolve once per active-scene entry regardless of tab.
  Only denied/restricted access and disabled Precise Location remain visible recovery actions; transient/confidence failures return to idle.
- The first successful live-region baseline produces no welcome, including after import.
  Preserve explicit DEBUG resets; cancelled/superseded lookups commit no history. Guard: `LocationWelcomeModelTests`.
