# WhereUI – Module Shape

WhereUI owns Where's presentation and observable models. Read the [feature contract](../AGENTS.md) and [root contract](../../AGENTS.md).
Its [README](README.md) describes the API; the required task references below own local behavior.

## Required task guidance

Read the matching instructions before changing or reviewing that behavior, including its tests and callers outside this directory.

| Task | Required guidance |
| --- | --- |
| Unit tests, image snapshots, test fixtures, or coverage changes | [Test contracts](Tests/AGENTS.md) |
| Settings, feature discovery, icons, updates, backup export, or diagnostic controls | [Settings contracts](Sources/Settings/AGENTS.md) |
| Launch, compatibility, reset, installation sidecars, log retention, or scope models | [Launch and installation-context contracts](Sources/Launch/AGENTS.md) |
| Developer tools, Inspector, demo controls, or Flyover | [Developer and Flyover contracts](Sources/Developer/AGENTS.md) |
| Calendar, Your Year, Timeline, or scene report publication | [Calendar and timeline contracts](Sources/Year/AGENTS.md) |
| GPS correction reviews, flight notices, or point actions | [Flight-review contracts](Sources/Resolution/AGENTS.md) |
| Artwork, styling, themes, shared controls, or motion | [Shared presentation contracts](Sources/Shared/AGENTS.md) |
| Locations, Elsewhere, adaptive panes, card ranking, or estimates | [Locations and adaptive-pane contracts](Sources/Primary/AGENTS.md) |
| Planned stays, forecasts, estimated-time controls, or Home presentation | [Planning presentation contracts](Sources/Forecasting/AGENTS.md) |

## Observable ownership

- Own presentation observables at the smallest stable screen, sheet, or flow that serves their consumers.
  Keep shared projections and drafts in the scene or flow that must preserve them across navigation or layout changes.
- Use [`ObservableHostingView`](Sources/Shared/ObservableHostingView.swift) when a view-owned model should be created only after its destination mounts.
  Give the host a new identity when a different input needs a fresh model. Use `@State` directly for simple view-local state.
- Drive visibility-sensitive work separately from model lifetime. Cancel obsolete reads and suppress late presentation.
  Keep accepted work that must finish after dismissal with the owning service or coordinator.

## Scope & dependencies

- WhereUI maps Core's persisted `RegionSymbol` values to SFSafeSymbols'
  `SFSymbol` and re-exports SFSafeSymbols for its presentation API consumers.
- Composition is the one exception: `WhereScope` and `WhereModel` decide which
  world the app is logged in to and assemble it. That's launch wiring, not
  domain logic — see [Scopes and the launch](../Guidance/launch.md#scopes-and-the-launch).
- Consumers (`WhereWidgets`, `WhereIntents`) get Broadway *through* WhereUI.
  They must **not** link `BroadwayUI`/`BroadwayCore` themselves (root
  [double-link rule](../../.agents/references/targets.md#never-double-link-a-product-whereui-already-carries)).
  That is why `whereBroadwayRoot()` lives here rather than being called as
  `broadwayRoot` at each site.
