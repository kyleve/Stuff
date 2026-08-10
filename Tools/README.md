# Stuff Tools

`Tools/Package.swift` is the independent macOS command-line package behind the
repository's migrated developer commands. Familiar root paths remain the
user-facing interface; each migrated command is a small shim that dispatches
into the `stuff` executable here.

The package is intentionally separate from the root application package. A tool
build resolves only ArgumentParser and Subprocess, never the iOS application
graph, and tool-only dependencies stay out of shipping targets.

## Development

```bash
swift test --package-path Tools
python3 -m unittest discover -s Tools/Tests -p 'test_*.py'
ruby -e 'Dir["Tools/Tests/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
Tools/run xcstrings --help
```

`Tools/run` uses the committed `Package.resolved` without automatic dependency
updates. Update dependencies explicitly with `swift package resolve
--package-path Tools`, then regenerate the app attribution report because these
packages are credited as development tools.

## Migrated commands

- `./xcstrings` owns byte-identical String Catalog normalization.
- `./simulator` owns typed `simctl` decoding, checkout identity, registry
  provenance, bounded locking, boot waiting, and exact-target deletion. Unowned
  devices are reported but never deleted automatically.
- `./test` derives affected bundles from Tuist's JSON graph plus SwiftPM's
  package dump, then shares the simulator resolver and streams raw `xcodebuild`
  output through a directly tested progress reporter. A successful process that
  matched zero tests is still a failed run.
- `./profile` keeps clean-build, unit-test, and serial snapshot-test timing as
  separate legs. It reads typed xcresult test cases, parses Xcode's build-timing
  summary and type-check warnings, and can retain CI-shaped separate DerivedData.
- `./flaky` retains warm DerivedData while treating suite and isolated test
  failures as report data. Typed xcresult aggregation identifies only tests that
  both pass and fail; prerequisite and build failures still exit nonzero.
- `./icons` validates complete app-catalog, preview-catalog, and manifest outputs
  before a same-filesystem transaction replaces anything. A failed commit rolls
  every target back, and `--dry-run` performs validation without staging files.
- `./Where/install` keeps signing, build, exact physical-device selection,
  installation, and launch as typed steps. It decodes `devicectl`'s current
  properties schema and offers a no-signing, no-device-query `--dry-run`.
- `./Ledger/install` validates the fixed destination and complete app shape,
  terminates only the exact installed executable with bounded escalation, and
  replaces it from `/Applications`-local staging with rollback. Its `--dry-run`
  performs no build, process, filesystem, or launch operation.

## Why `test` uses raw xcodebuild

The command deliberately uses `xcodebuild build-for-testing` followed by
`test-without-building`. Tuist's formatter can omit the detail block following
Swift Testing's generic “Issue recorded” headline, including snapshot mismatch
paths. The raw invocation also sets `-collect-test-diagnostics never`; without
that flag, a failing simulator test can spend ten minutes attempting to collect
diagnostics before returning. Snapshot timing and difference reports likewise
consume detail lines from the unformatted log.

`./profile` also requires raw output because Tuist's formatter omits
`-showBuildTimingSummary`; its per-test durations come from `xcresulttool`, not
human-formatted log text.

Affected-bundle selection does not parse `Project.swift`. Tuist's pinned
`graph --format json` output is authoritative for schemes, targets, sources,
and host dependencies; `swift package dump-package` supplies the local package
target closure that Tuist leaves with Xcode's SwiftPM integration.

## Structure

- `Sources/StuffTool` is the executable composition root.
- `Sources/StuffToolCore` contains commands, typed external formats, and injected
  process/filesystem infrastructure.
- `SwiftTests/StuffToolCoreTests` contains fast hermetic Swift Testing suites.
- `tla_check.py` contains the importable TLA+ manifest/TLC runner behind the
  bootstrap-only root launcher.
- `Tests` covers retained Python and Ruby tools against temporary fixture
  repositories; those tools remain in their existing language when they are
  cross-platform or already have an appropriate structured implementation.
