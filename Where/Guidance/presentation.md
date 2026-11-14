# Presentation contracts

## Navigation

The logged-in shell is `MainTabs`. Its tabs are Locations, optional Elsewhere,
Your Year, and Settings, in that order. Show Elsewhere only when the selected
year has visits outside the configured primary set. Keep it available during
same-year refreshes; return to Locations if its last visit disappears. New
screens use a pushed destination, a sheet, or a Settings row inside this shape. `MainTabs` passes the
scene-scoped `YearReportModel` by explicit init injection. The always-on
`WhereSession` coordinator travels in the environment. Settings is a
typed-route list (`SettingsSearch.swift`. Every switch is exhaustive). A
new drill-in is a set of compile errors to fill in. About stays the last
block. The demo-mode exit is the first.

Data, Privacy & Diagnostics, and About lead with the shared privacy passport.
Derive its detail from process-effective reporting channels, not saved pending
choices. Hide the persisted diagnostics destination in demo mode. About still
discloses the real process state.
The About screen renders three live sources. They are the generated attribution
report (`WhereCore.AppAttribution`), `RegionDataSource`, and `BuildInfo`.
Never hard-code a list in the view. A missing report or unstamped build
renders an honest empty state. Shipped libraries stay a separate section
from development tools. Keep its final passport sign-off linked to the public
project repository. Design and rationale: PR #140.

## Localization

All user-facing copy resolves through each module's `Localizable.xcstrings`
via Xcode's generated `LocalizedStringResource` symbols. A typo'd or removed
key is a compile error. Add a key as a **manual** entry first (so its symbol
generates). Then reference `.thatSymbol`. Never use a raw
`String(localized: "literal.key")`, a hand-maintained key facade, or an
English literal in `Text` / `errorDescription`.

- **WhereUI:** reference symbols directly. Composition, pluralization, and
  number/coordinate formatting go through
  [`WhereFormat`](../WhereUI/Sources/Shared/WhereFormat.swift).
- **RegionKit:** region names resolve dynamically from `regions.json`
  (+ optional `localizationKey`). That is the one deliberate exception to static
  symbols (see [`RegionKit/AGENTS.md`](../RegionKit/AGENTS.md)).
- **Extensions** use their own generated symbols for chrome and WhereUI's
  public helpers for shared copy. **DEBUG-only UI** is still localized.
- The catalogs carry a few value-less **auto-extracted** entries (`""`,
  `%lld`). They are Xcode's, not ours. An IDE build re-adds a deleted one. Remove
  the *source* literal instead. Catalogs stay byte-identical to Xcode's own
  serialization (root [Formatting](../../AGENTS.md#formatting)).

## UI construction

Load the repo [`building-ui`](../../.agents/skills/building-ui/SKILL.md) skill for
view/model placement, reuse, Broadway styling, layout, accessibility,
localization, previews, and image coverage. WhereUI previews use
[`PreviewSupport`](../WhereUI/Sources/Preview/PreviewSupport.swift). Use
synchronous, in-memory fixtures. Never use disk, CloudKit, or CoreLocation.
