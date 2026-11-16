# WhereUI test contracts

Read the [module contract](../AGENTS.md) and the [repository contract](../../../AGENTS.md) first.

## Testing

Keep Developer Overlay snapshots scene-backed so native glass retains its scene geometry. Guard: `DeveloperOverlaySnapshotTests`.

Hosted tests that traverse SwiftUI accessibility must link and import
`AccessibilitySnapshotParser` so a fresh simulator initializes its accessibility
runtime. Guard: `CalendarContentViewTests`.

`Tests/Support/TestStore.swift` and `AdaptivePaneLoadFixture.swift` are shared by the unit and image bundles through `Project.swift`.
Keep support fixtures outside `SnapshotTests/`, whose Swift files each declare one matching suite. Use the store's read gates and failures for adaptive loading snapshots. Keep fixture setup and completion independent for each configuration.

`WhereStylesheetTests` covers trait-aware derivation, calculations, and semantic accessibility constraints.
`WhereStylesheetEnvironmentTests` covers the `@Environment(\.stylesheet)`
glue and `whereBroadwayRoot()` seeding, including the WhereWidgets path.
Follow [Broadway coverage guidance](../../../.agents/skills/building-ui/references/broadway.md) for token changes.

`WhereFlyoverCatalogTests` pins the catalog against the colocated registrations
assembled by `WhereFlyoverCatalog`. Add a registration beside every new
top-level screen. List its type in the appropriate catalog group. Flyover
frames share one `WhereFlyoverWorld`. Synthetic preview models are reserved for
states the seeded demo cannot express.
When registrations, routes, or default variants change, run
`WhereFlyoverCatalogTests` alongside the affected screen suites.
Keep the full Where Flyover overview out of image snapshots. Use individual screen
suites for content and the shared Flyover suite for the browser.

Distinct screen, widget, and app-flow rendering is covered by selected image
snapshots under [`SnapshotTests/`](../SnapshotTests). Those build as this module's
`WhereUISnapshotTests` bundle in the shared `StuffSnapshotTests` scheme and CI
job, deliberately outside `Stuff-iOS-Tests` (root
[`AGENTS.md`](../../../.agents/references/targets.md#targets)). Declarations use the helpers in
[`Sources/Preview/WhereSnapshot.swift`](../Sources/Preview/WhereSnapshot.swift).
Follow `building-ui` for authoring and the repo `running-tests` skill for
recording/reviewing references. Apply [SnapshotKit's coverage policy](../../../Shared/SnapshotKit/AGENTS.md):
Explore Features galleries share layout coverage; retain focused large-type checks
for dense content. Shared InstallerKitUI owns updater scenario coverage; Where's
wrapper owns branding and integration. Preserve all updater preview/Flyover states
through the shared fixture builder when narrowing its recorded cases.

For new or changed themed components, use `whereThemeSnapshot` for one comparison
sheet containing every supported theme. Use representative states across light/dark
and relevant accessibility configurations; keep each configuration in a separate
sheet. Use narrower matrices for additional states. Keep production component
width and behavior, including artwork readiness and informational gradients.

Keep per-theme full-screen coverage for critical integration screens such as
Locations, or screens whose composition changes materially with the theme.
Do not duplicate entire screen matrices to exercise a child component's surface.
Keep appearance-picker selection-state coverage. Native chrome and unchanged
lightweight widget/snippet surfaces do not need duplicate theme cases.

`whereSnapshot` defaults to Standard and preserves its existing reference paths.
Other themes use stable consumer-owned groups (`flat/` for `.alternate`). Mixed-theme
sheets use `themes/`. Special trait images use `other/` inside the selected group.
Never derive the folder from a localized label or rename a persisted theme identity.
