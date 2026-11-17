# Remove RTL image cases

Status: executing
Dependencies: none.
Requirements: [R-01, R-04, X-01](README.md#requirements-and-scope).

Remove three MainTabs, one Settings, and two onboarding theme-selection RTL configurations and their six PNG references. Existing presets and export defaults contain no RTL variants; document that default policy. Preserve explicit direction support and its unit contracts.

Verify no RTL image references or provider configurations remain. Run `SnapshotConfigurationTests` plus the three affected image suites with `--record never`. Include CalendarContentView and YearView in the image run to establish the unchanged calendar baseline for plan 02. Compare retained identities with references. Run normal architecture and applicable formatting/symbol checks.

Review, 2026-11-17: removing an explicit matrix member has no production effect. The source inventory matches exactly six reference files. No new architecture or diagram is applicable. This step may commit independently before calendar changes.

## Evidence

Removed exactly the six inventoried configurations and PNGs. No `rightToLeft` configuration remains in WhereUI's source providers. Shared presets and Flyover defaults already omit RTL. Explicit direction support and its API tests remain.

The combined validation/baseline run passes 26 SnapshotConfiguration unit tests and eight image functions in five suites. Retained RTL-owning coverage is 58 MainTabs, 16 Settings, and 10 onboarding captures. CalendarContentView (63 captures) and YearView (12) establish plan 02's baseline. Total: 159 captures, 1,205,599,602 pixels, 205 tiles, no capture retries. `./swiftformat --lint` and `./sf-symbols --lint` pass.

Command: `TEST_WORKDIR=/private/tmp/stuff-snapshot-reviewability-baseline-20261117 ./test --only SnapshotKitTests/SnapshotConfigurationTests --only WhereUISnapshotTests/MainTabsSnapshotTests --only WhereUISnapshotTests/SettingsViewSnapshotTests --only WhereUISnapshotTests/OnboardingThemeSelectionViewSnapshotTests --only WhereUISnapshotTests/CalendarContentViewSnapshotTests --only WhereUISnapshotTests/YearViewSnapshotTests --no-generate --timings --review --record never`. Normal architecture and applicable host checks pass.

Resume: commit this verified step; independent review and publication follow plan 02.
