# 01 — Unit tests and guidance

- Status: complete
- Depends on: none
- Shared context: [Overview](README.md)
- Requirements: R-01, R-02, R-05; exclusions X-01 and X-02 apply.

## Deliverable and steps

1. Remove the 28 copied-default tests from Where, Flyover, and Periscope stylesheets.
2. Trim mixed stylesheet tests to accessibility constraints, trait derivation, and calculation behavior.
3. Remove 14 WhereUI hosting-only tests, About's unrelated data-list assertion, and seven synthesized-value checks in `BAccessibilityTests`.
4. Remove unused imports, helpers, and empty files left by those deletions.
5. Correct guidance at its existing owners: Swift conventions, Broadway, previews, SnapshotKit, WhereUI, running-tests, and Explore Features.
6. Preserve external skill contents. State repository test-selection policy in the repository-owned conventions.

No production data flow or architecture changes are required.

## Acceptance and verification

- Retain stylesheet root/environment propagation, trait-dependent layout, contrast, minimum targets, and theme inheritance.
- Retain `BAccessibility` provider, observer, and stream behavior.
- Run affected retained stylesheet, accessibility, and About suites through `./test --only`.
- Run `./swiftformat --lint` on changed Swift files.
- Run `mise exec ruby -- ./sync-agents`, then `mise exec ruby -- ./sync-agents --check`.
- Validate changed owned skills with skill-creator's `quick_validate.py`.
- Review the diff and publish the coherent step.

## Recovery

Compare each removed function with baseline `2193072f6`. Preserve unrelated local changes.
If a removed test owns a unique behavior guard, retain that assertion and repeat its affected checks.

## Progress and evidence

- Baseline guidance check passed: 57 instruction files, 13 owned skills, largest chain 24,434/28,672 bytes.
- Removed the 50 audited declarations and consolidated six mixed token tests into one minimum-size test: 55 fewer declarations.
- Removed unused helpers/imports and six empty test files. Retained calculation tests now avoid copies of authored defaults.
- SwiftFormat lint passed for all six edited Swift files.
- Guidance synchronization passed: 57 instruction files, 13 owned skills, largest chain 24,530/28,672 bytes.
- Skill-creator validation passed for building-ui, running-tests, and update-explore-features with temporary PyYAML 6.0.3.
- Independent source/diff review found no actionable issues. Its wording suggestion clarified that semantic equality contracts remain valid coverage.
- Focused iOS checks passed: 72 tests on Xcode 27.2 / iOS 27.2.
  `./test` selected these suites with repeated `--only` arguments:
  `BroadwayCoreTests/BAccessibilityTests`, `BAccessibilitySettingsProviderTests`, `BAccessibilityObserverTests`, and `BAccessibilityChangesTests`;
  `FlyoverTests/FlyoverStylesheetTests`;
  `PeriscopeToolsTests/PeriscopeStylesheetTests` and `PeriscopeStylesheetEnvironmentTests`;
  `InstallerKitUITests/InstallerStylesheetTests`;
  `WhereUITests/WhereStylesheetTests`, `WhereStylesheetEnvironmentTests`, and `AboutSettingsViewTests`.
- The wrapper also passed 29 architecture tests, architecture lint, 17 Flyover web tests, attribution, and 16 backup-upgrader regressions.
- Test log: `/private/tmp/stuff-test-reduction-unit.log`; results: `where-test-e901f1e05db2` in the checkout's temporary test directory.
- Published as `7c3a06da1` on `codex/test-maintenance-reduction` in [PR #505](https://github.com/kyleve/Stuff/pull/505).

## Resume point

Complete. Continue with [02](02-snapshot-phase-one.md).
