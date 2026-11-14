# WhereUI – Module Shape

WhereUI is the SwiftUI layer of the Where feature. It owns the screens, the
shared components and widget views, and the `@Observable` view models that
orchestrate `WhereCore` for them (`WhereModel`, the `WhereSession`
coordinator, and the scoped `YearReportModel` / `ResolveModel` /
`BackupModel` / `RemindersSettingsModel` / `DevicesSettingsModel` /
`OnboardingFlowModel` / `OnboardingImportRecoveryModel` /
`LocationForecastModel` / `DiagnosticReportingSettingsModel`).
Layering, localization, preview, and testing conventions live in the feature
[`Where/AGENTS.md`](../AGENTS.md). Read that and the root
[`AGENTS.md`](../../AGENTS.md) first.


## Required task guidance

Read the matching instructions before changing or reviewing that behavior, including its tests and callers outside this directory.
Read only the rows relevant to the task. These references preserve required contracts.

| Task | Required guidance |
| --- | --- |
| Unit tests, image snapshots, test fixtures, or coverage changes | [Test contracts](Tests/AGENTS.md) |
| Settings, feature discovery, icons, updates, backup export, or diagnostic controls | [Settings contracts](Sources/Settings/AGENTS.md) |
| Launch, reset, installation sidecars, log retention, or scope models | [Launch and installation-context contracts](Sources/Launch/AGENTS.md) |
| Developer tools, Inspector, demo controls, or Flyover | [Developer and Flyover contracts](Sources/Developer/AGENTS.md) |
| Calendar, Your Year, Timeline, or scene report publication | [Calendar and timeline contracts](Sources/Year/AGENTS.md) |
| GPS correction reviews, flight notices, or point actions | [Flight-review contracts](Sources/Resolution/AGENTS.md) |
| Artwork, styling, themes, shared controls, or motion | [Shared presentation contracts](Sources/Shared/AGENTS.md) |
| Locations, Elsewhere, adaptive panes, card ranking, or estimates | [Locations and adaptive-pane contracts](Sources/Primary/AGENTS.md) |
| Planned stays, forecasts, estimated-time controls, or Home presentation | [Planning presentation contracts](Sources/Forecasting/AGENTS.md) |

## Scope & dependencies

- Presentation layer only. No domain rules, persistence, or store I/O here
  ([Layering](../AGENTS.md#layering)). Dependencies live in the root
  [`Package.swift`](../../Package.swift).
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
