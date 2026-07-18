# WhereUI – Module Shape

WhereUI is the SwiftUI layer of the Where feature: the screens, the shared
components and widget views, and the `@Observable` view models that orchestrate
`WhereCore` for them (`WhereModel`, the `WhereSession` coordinator, and the
scope-tiered `YearReportModel` / `ResolveModel` / `BackupModel` /
`RemindersSettingsModel`). Its layering, localization, preview, and testing
conventions live in the feature [`Where/AGENTS.md`](../AGENTS.md) — read that and
the root [`AGENTS.md`](../../AGENTS.md) first. This file adds only what those
don't cover: how the module's design system (`WhereStylesheet`) is used and
extended, and how its snapshot suites are organized (see
[Testing](#testing)).

## Scope & dependencies

- Presentation layer only — no domain rules, persistence, or store I/O here
  (see [Layering](../AGENTS.md#layering)). Dependencies live in the root
  [`Package.swift`](../../Package.swift).
- Consumers (`WhereWidgets`, `WhereIntents`) get Broadway *through* WhereUI (a
  dynamic framework) and must **not** link `BroadwayUI`/`BroadwayCore`
  themselves — a second copy would split Broadway's type-keyed environment
  metadata and the stylesheet would stop resolving across the boundary. This
  is why `whereBroadwayRoot()` lives here rather than being called as
  `broadwayRoot` at each site.
- Continuous/looping motion (repeat-forever pulses, `TimelineView(.animation)`,
  typewriter reveals) must consult the shared `@MotionIsStatic` helper
  ([`Sources/Shared/MotionIsStatic.swift`](Sources/Shared/MotionIsStatic.swift))
  for its static end-state — never hand-roll the
  `\.accessibilityReduceMotion` + `\.isCapturingSnapshot` pair.

## Design system — `WhereStylesheet`

`WhereStylesheet`
([`Sources/Shared/WhereStylesheet.swift`](Sources/Shared/WhereStylesheet.swift))
is the single home for the app's appearance tokens — geometry, fonts, colors,
motion — expressed as a Broadway `BStylesheet`. It replaced the scattered inline
literals and the former `UIConstants` bag: a new appearance value belongs here,
not back inline in a view.

### Using tokens

- Read tokens in a view with `@Environment(\.stylesheet) private var
  stylesheet` (e.g. `stylesheet.spacing.medium`). The active sheet is seeded
  by `whereBroadwayRoot()` at the app root and in each Broadway-root-less
  consumer (WhereWidgets); with no root present (isolated previews, code off
  the `View` tree) resolution falls back to `WhereStylesheet.default` — use
  that static directly in layout helpers and tests.
- **Resolve a variant once.** For a component with more than one look, vend a
  resolved sub-spec and read it into a single property rather than branching
  through the body: `RegionSummaryCard` reads `stylesheet.card[variant]` into a
  `card` so its render is straight-line, with no `compact ? … : …` scattered
  across ~30 values.

### Adding tokens — prefer per-component style groups

Group a component's whole appearance into one nested `Equatable` struct instead
of adding loose properties to the top level. The existing groups —
`CardStyle` / `CardStyles`, `CalendarStyle`, `AppIconStyle`, `TimelineStyle`,
`RegionMapStyle`, `RegionPickerStyle` — are the template. To add one:

1. Define the struct in a `WhereStylesheet` extension with a doc comment saying
   which component it styles and any invariants; nest further structs for
   sub-parts (e.g. `CalendarStyle.MonthStyle`, `AppIconStyle.PanelStyle`).
2. Give it a `static let standard` holding the fixed geometry, and add a stored
   property on `WhereStylesheet` defaulted to it.
3. If a look varies (the `compact` card), model the axis as a `Variant` enum and
   expose a `subscript` on the styles struct (see `CardStyles`) so callers read
   one resolved spec — don't thread a `Bool` through the view.

Reach for a shared group only for genuinely cross-component values: the generic
point scale on `Spacing`, one-off element sizes on `Size`, app-wide colors not
owned by a single component on `Palette`, the few bespoke display faces on
`Typography`, and animation tokens on `Motion`. Per-region tints stay in
`RegionStyle` (not the stylesheet); adaptive system roles (`.secondary`) and
`.accentColor` stay inline.

`RegionStyle` is **data-driven** and resolved through the environment: views
read `@Environment(\.regionStyles)` (a `RegionStyleResolver`) and call
`regionStyles.style(for: region)` — there is no global `region.style`. The
resolver is seeded by `whereBroadwayRoot(regionStyles:)`: the app passes
`WhereSession`'s live resolver (updated on launch + `changes()`), the widget
process one built from its `WidgetSnapshot`, and App Intents snippets one from
their services; the default empty resolver yields the fallback looks
(`RegionAppearanceCatalog.defaultAppearance(for:)`) for previews and the
region-map viewer. The catalog also owns the selectable color/emoji/symbol
option lists the picker shows. Don't reintroduce a global accessor or a
hardcoded per-region look in a view.

### Trait-aware tokens

Most tokens are fixed, but a slice derives from the `BContext` traits in
`init(context:)`. Start from the fixed set (property defaults / `.standard`),
then adjust only the reactive slice, so a default/system context reproduces
`WhereStylesheet.default`. Current derivations: larger day-grid tap targets at
accessibility Dynamic Type sizes, and a flattened card glow under Reduce
Transparency. Views still decide *when* to apply motion and honor Reduce Motion
(they pick `motion.reducedReveal`, skip `motion.captionFade`) — the tokens carry
the full-motion values.

`WhereThemes` is deliberately empty for now — the sheet derives from traits, not
themes. It is the seam a future app-wide or seasonal palette/typography theme
would plug into.

### What not to do

- **Don't borrow another component's style.** A component must never read a value
  off another component's group to dodge defining its own — e.g. `TimelineStyle`
  does not reach into `CardStyle` for a corner radius. If a component needs a
  value, it gets its own property (or its own style struct); the cost of adding
  a struct is the point, not something to route around. Only genuinely
  cross-cutting values belong on the shared scales (`Spacing`, `Size`, `Palette`,
  `Typography`, `Motion`) — and a token there should read as shared, not as one
  component quietly depending on another's geometry.
- **Don't hardcode appearance in a view**, and don't collect unrelated constants
  into a flat grab-bag (the old `UIConstants` smell). A new geometry / font /
  color / motion value lands on the owning component group or a shared scale.
- **Don't branch a variant through the body.** Model the axis as a `Variant` enum
  plus a `subscript` and read one resolved spec (see [Using
  tokens](#using-tokens)) — don't scatter `compact ? … : …` or thread a `Bool`
  down the view.
- **Don't bake trait-derived values into the defaults.** `.standard` / property
  defaults hold the fixed set; apply the reactive slice only in `init(context:)`,
  so a default/system context still reproduces `WhereStylesheet.default`.
- **Don't put per-region or adaptive-system colors in the sheet.** Per-region
  tints stay in `RegionStyle`; adaptive system roles (`.secondary`) and
  `.accentColor` stay inline.

## Testing

`WhereStylesheetTests` pins every token's default value and the trait-aware
derivations (resolved synchronously off a `BContext`);
`WhereStylesheetEnvironmentTests` covers the `@Environment(\.stylesheet)` glue
and the `whereBroadwayRoot()` seeding, including the WhereWidgets path. Adding,
renaming, or retuning a token means updating those assertions in the same
change. Broader WhereUI testing conventions (hosted bundles, `PreviewSupport`,
required previews) live in the feature [`Where/AGENTS.md`](../AGENTS.md).

Screens, widgets, and app-flow surfaces are pinned as matrixed image snapshots
in the `WhereUISnapshotTests` bundle ([`SnapshotTests/`](SnapshotTests)) — that
bundle, not hosting smoke tests, owns "does this screen render". Each view
declares its matrix once via a `SnapshotProviding` conformance in
[`Sources/Preview/`](Sources/Preview) (`ScreenSnapshots.swift`,
`WidgetSnapshots.swift`, `AppFlowSnapshots.swift`), which also drives the
`#Preview` cutsheets. The bundle runs in its own `WhereUISnapshotTests` scheme
and CI job, deliberately outside `Stuff-iOS-Tests` (see `Project.swift`). To
re-record a reference, delete the PNG under `SnapshotTests/__Snapshots__/`
(LFS-tracked) and run the scheme — the suites record `.missing`, and a
recording run fails by design so it can't pass as green. (Bulk re-records
after an intentional UI change can instead forward
`TEST_RUNNER_SNAPSHOT_RECORD=failed` — see the
[SnapshotKitTesting README](../../Shared/SnapshotKitTesting/README.md#recording).)
