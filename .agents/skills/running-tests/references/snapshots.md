# Snapshot validation

## Select coverage

Use `./test --snapshots --only Bundle/Suite` for the owning component and relevant screen integration suites.
Changes to SnapshotKit configuration or capture code need their regression suites and affected rendering coverage.
Reserve the full image suite for changes whose effects span the shared renderer or application appearance.
Documentation-only edits and test deletions do not automatically require every image bundle.

## Capture and review

- Use the Xcode major.minor in [`.xcode-version`](../../../../.xcode-version); `./test` checks it before setup.
- Run captures serially on one Mac. Its simulators share a render server; CI parallelism uses isolated VMs.
- Use `--review` to inspect differing pixels and `--timings` for capture cost.
- Fix the render before recording. A stable placeholder still needs the fixture's readiness hook; pixel settling does not prove async completion.
- Read [SnapshotKitTesting's contract](../../../../Shared/SnapshotKitTesting/AGENTS.md) when changing capture infrastructure or diagnosing settling, hosting, or comparison behavior.

## Comparison sheets

Run component suites and selected screen integration suites.
Inspect each theme panel in light/dark and relevant accessibility sizes before recording.
Preserve PNG panel-map metadata. A panel must fail at its own pixel-area budget even if the complete sheet would pass.
Keep ungrouped reference paths and nest special traits inside explicit theme groups.
Module instructions own component versus screen coverage.

Timings count actual panel captures; composing a sheet does not avoid rendering them.

## Matrix changes

Compare retained case/configuration identities with the remaining references.
Use `--record never` for unchanged captures.
Record new or intentionally reframed subjects in a separate focused run, inspect them, then run the final assertions.
