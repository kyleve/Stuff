# Stuff

Random apps and stuff.

## Requirements

- Xcode 27+ (a full Xcode.app, not just the Command Line Tools)
- iOS 26.0+
- [mise](https://mise.jdx.dev) — pins Tuist, SwiftFormat, and Ruby.
  `./ide --bootstrap` installs it (see below).

## Getting started

On a fresh machine, run the one-shot bootstrap.
It checks that Xcode is installed and selected.
If `mise` is missing, it installs it via the official installer (no Homebrew required).
It installs the pinned tools (Tuist, SwiftFormat, Ruby).
Then it sets Git hooks, runs `sync-agents --install`, and generates the Xcode project:

```bash
# One-shot setup for a new laptop (add -i to fetch Tuist package deps,
# --team-id ABCDE12345 for on-device signing — see below)
./ide --bootstrap
```

When bootstrap installs `mise`, it also adds `mise activate` to your shell rc
(zsh/bash) so `mise` and the pinned tools are on `PATH` in new terminals.
Restart your shell (or `source ~/.zshrc`) afterwards.
On other shells, add activation manually per the [mise docs](https://mise.jdx.dev/getting-started.html).

If `mise` is already installed, regenerate the project:

```bash
# Generate the Xcode project (also sets Git hooks and runs sync-agents --install)
./ide

# Or install Tuist package dependencies first, then generate
./ide -i
```

If you run `./ide` without `--bootstrap` and `mise` is not found, the script fails fast.
It points you back at `./ide --bootstrap`.
If you manage `mise` yourself, run `brew install mise` (or the [official installer](https://mise.jdx.dev)).
Then run `mise install`.

Run tests with `./test` (or open the generated workspace in Xcode).
With no arguments it runs only the bundles your changes affect.
It uses the simulator this checkout owns.
`./simulator` creates that device on its first run and boots it on every run.
It streams progress while it goes:

```bash
./test                  # just what your change affects
./test WhereCoreTests   # one bundle
./test --all            # the whole unit suite
./test --snapshots      # the image-snapshot suite
./test --everything     # both, as CI runs it
```

See `./test --help` for the rest.
It includes `--timings` and `--review` for reading a snapshot run.

Every checkout gets its own simulator.
That includes a second clone or a worktree.
Two runs on one machine never fight over booting, installing to, or erasing the same simulator.
Run `./simulator --list` to show them with their owning checkouts.
Run `./simulator --prune` (`--dry-run` to preview) to clean up after a checkout you deleted.
See `./simulator --help`.

Codex-managed worktrees use the checked-in local environment at
`.codex/environments/environment.toml`.
Setup fetches `origin/main`.
It warns without changing the checkout when its `HEAD` does not contain the latest main.
The **Update to latest main** toolbar action safely fast-forwards a checkout directly behind main.
It refuses divergent feature history.
On macOS the environment also runs `./ide --bootstrap --no-open`.
It offers project generation, affected tests, and format lint actions.
It removes only that checkout's simulator on cleanup.
`.worktreeinclude` copies the gitignored `.mise.local.toml` signing override from the source checkout into each new managed worktree.

Where's production architecture is checked with Bumper Bowling through the root Swift package:

```bash
swift run bumper config .
swift run bumper test .
swift run bumper lint . --timings
```

The executable configuration is in [`BumperBowling.swift`](BumperBowling.swift).
The enforced invariants and repair guidance are cataloged in [`.bumper/RULES.md`](.bumper/RULES.md).

Run `./profile` to see where build and test time goes.
It prints the slowest build phases, the slowest tests (per bundle), and any slow type-check sites.
It only reports.
It never fails.
See `./profile --help` for flags (`--build-only`/`--tests-only`, `--no-snapshots`, `--device`/`--os`, `--top`, thresholds).

Run `./flaky` to hunt down flaky tests.
It runs the whole suite several times.
It tight-loops (in isolation) any test that ever failed.
It records the tests that both pass and fail (with flake counts) in [`FLAKY_TESTS.md`](FLAKY_TESTS.md).
Like `./profile` it is report-only.
See `./flaky --help` for flags (`--suite-runs`, `--iterations`, `--device`/`--os`, `--no-update`, `--top`).

The `./ide` script sets `core.hooksPath` to `.githooks`.
The pre-commit hook formats staged Swift with SwiftFormat.
It runs `./sync-agents --git-add` so generated Claude files stay in sync with `AGENTS.md`.

## Signing for on-device builds

The checked-in project intentionally has **no** development team.
Building to a simulator works for everyone.
Nothing machine-specific lands in Git.
To build to a physical device you must supply your Apple Developer Team ID.

`Project.swift` reads it from the `TUIST_DEVELOPMENT_TEAM` environment variable.
When present, it stamps it into the generated project as `DEVELOPMENT_TEAM`.
The value lives in `.mise.local.toml`.
That file is a local, **gitignored** mise config.
`mise exec -- tuist generate` (i.e. `./ide`) picks it up automatically.
Your team survives every regeneration.
If no team is set (CI, fresh clones), no `DEVELOPMENT_TEAM` is written.
Xcode behaves as before.

Set it once:

```bash
# Writes TUIST_DEVELOPMENT_TEAM to .mise.local.toml, then regenerates
./ide --team-id ABCDE12345
```

Find your Team ID in Xcode › Settings › Accounts (the "Team ID" column) or at
[developer.apple.com/account](https://developer.apple.com/account) under
Membership details. You can also edit `.mise.local.toml` by hand:

```toml
[env]
TUIST_DEVELOPMENT_TEAM = "ABCDE12345"
```

## Project structure

```
Package.swift       Local Swift package (StuffCore, LifecycleKit, WhereCore, WhereUI, TestHostSupport, …)
BumperBowling.swift Executable Where architecture policy
.bumper/            Repo-owned Bumper shapes, rules, tests, and catalog
Project.swift       Tuist manifest (Where app, StuffTestHost, test bundles → SPM)
Tuist.swift         Tuist configuration
.mise.toml          Pins the Tuist, SwiftFormat, and Ruby versions
.mise.local.toml    Local mise overrides, gitignored (e.g. TUIST_DEVELOPMENT_TEAM)
.swiftformat        SwiftFormat rules
.codex/             Codex managed-worktree setup, cleanup, and actions
.worktreeinclude    Ignored local files copied into Codex-managed worktrees
ide                 Dev script – bootstrap (mise + tools), hooks, sync-agents, tuist generate
swiftformat         Run SwiftFormat via mise (default: format `.`)
sync-agents         Sync AGENTS.md → CLAUDE.md and .claude/skills/
simulator           Resolve/create this checkout's simulator, boot it, print its UDID
worktree            Check or safely fast-forward a checkout against origin/main
profile             Report build/test hot spots (see `./profile --help`)
flaky               Detect flaky tests, update FLAKY_TESTS.md (see `./flaky --help`)
FLAKY_TESTS.md      Flaky tests and their flake counts (generated by `./flaky`)
TODOs.md            Cross-area backlog — and the format every TODOs.md follows
INBOX.md            Raw, unverified notes awaiting triage into a TODOs.md
MODULE_AUDIT.md     Dated module inventory and themes — derived, carries no TODOs
.githooks/          Git hooks (pre-commit)
.cursor/            Cloud agent environment (environment.json + install.sh)
.agents/            Agent skills — repo-owned plus the external manifest
AGENTS.md           Repository shape for AI agents
Shared/             Shared modules (Broadway, Periscope, LifecycleKit, …) — one
                    folder each, carrying its own README.md and AGENTS.md
Where/              The Where app, its modules, and its tests — same shape
```

## Acknowledgements

The Where module bundles offline region polygons under
[`Where/RegionKit/Sources/Resources/regions/`](Where/RegionKit/Sources/Resources/regions/).
US state boundaries come from
[eric.clst.org/tech/usgeojson](https://eric.clst.org/tech/usgeojson/)
(`gz_2010_us_040_00_5m.json`), converted from the
[US Census Bureau Cartographic Boundary Files](https://www.census.gov/geographies/mapping-files/time-series/geo/cartographic-boundary.html).
US Government works are in the public domain. See
[`Where/RegionKit/README.md`](Where/RegionKit/README.md) for per-file
provenance.

## License

Apache 2.0 – see [LICENSE](LICENSE).
