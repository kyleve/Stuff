# Stuff

Random apps and stuff.

## Requirements

- Xcode 27+ (a full Xcode.app, not the Command Line Tools)
- iOS 26.0+
- [mise](https://mise.jdx.dev) pins Tuist, SwiftFormat, ShellCheck, and Ruby.
  `./ide --bootstrap` installs it for you (see below).

## Getting started

On a fresh machine, run the one-shot bootstrap.
It checks that Xcode is installed and selected.
If `mise` is missing, it installs `mise` via the official installer (no Homebrew required).
It installs the pinned tools (Tuist, SwiftFormat, ShellCheck, Ruby).
Then it sets Git hooks, runs `sync-agents --install`, and generates the Xcode project:

```bash
# One-shot setup for a new laptop (add -i to fetch Tuist package deps,
# --team-id ABCDE12345 for on-device signing — see below)
./ide --bootstrap
```

When bootstrap installs `mise`, it also adds `mise activate` to your shell rc (zsh/bash).
Then `mise` and the pinned tools are on `PATH` in new terminals.
Restart your shell (or `source ~/.zshrc`) afterwards.
On other shells, add activation manually per the [mise docs](https://mise.jdx.dev/getting-started.html).

When `mise` is already installed, regenerate:

```bash
# Generate the Xcode project (also sets Git hooks and runs sync-agents --install)
./ide

# Or install Tuist package dependencies first, then generate
./ide -i
```

If `mise` is not found, `./ide` without `--bootstrap` fails fast and points you at `./ide --bootstrap`.
If you manage `mise` yourself, run `brew install mise` (or the [official installer](https://mise.jdx.dev)).
Then run `mise install`.

Run tests with `./test` (or open the generated workspace in Xcode).
With no arguments, `./test` runs only the bundles your changes affect.
It uses the simulator this checkout owns.
`./simulator` creates that device on its first run and boots it on every run.
It streams progress while tests run:

```bash
./test                  # just what your change affects
./test WhereCoreTests   # one bundle
./test --all            # the whole unit suite
./test --snapshots      # the image-snapshot suite
./test --everything     # both CI suites in one local run
```

See `./test --help` for the rest, including `--timings` and `--review` for reading a snapshot run.

Each checkout gets a device of its own (a second clone, a worktree, and so on).
Two runs on one machine never fight over booting, installing to, or erasing the same simulator.
`./simulator --list` shows devices with their owning checkouts.
`./simulator --prune` cleans up after a checkout you deleted.
Prune, delete, and recreate operations accept `--dry-run`.
See `./simulator --help`.

Codex-managed worktrees use the checked-in local environment at `.codex/environments/environment.toml`.
Setup fetches `origin/main` and warns without changing the checkout when its `HEAD` does not contain the latest main.
The **Update to latest main** toolbar action safely fast-forwards a checkout directly behind main.
It refuses divergent feature history.
On macOS the environment also runs `./ide --bootstrap --no-open`.
That hydrates the checkout's Git LFS snapshot references before generating the project.
It offers affected tests and format lint actions.
On cleanup it removes only that checkout's simulator.
`.worktreeinclude` copies the gitignored `.mise.local.toml` signing override from the source checkout into each new managed worktree.

Where's production architecture is checked with Bumper Bowling through the root Swift package:

```bash
./test --architecture-only
```

Normal `./test` invocations also run these architecture checks before other tests.
The executable configuration is in [`BumperBowling.swift`](BumperBowling.swift).
The enforced invariants and repair guidance are cataloged in [`.bumper/RULES.md`](.bumper/RULES.md).

To see where build and test time goes, run `./profile`.
It prints setup/build/test walls, the slowest build phases and tests, slow type-check sites, and per-phase snapshot capture costs.
The default reuses unit-build products for the snapshot build.
`--ci-shape` instead gives each scheme cold DerivedData like its independent CI job.
It only reports.
It never fails on slow numbers.
See `./profile --help` for the remaining scope, destination, and threshold flags.

CI assigns snapshot suites to isolated workers.
Each worker runs its assigned suites serially on one simulator.
Multiple snapshot simulators on one Mac contend for the same render server.
Do not run snapshots concurrently locally.

To hunt down flaky tests, run `./flaky`.
It runs the whole suite several times.
Then it tight-loops (in isolation) any test that ever failed.
It records the tests that both pass and fail (with flake counts) in [`FLAKY_TESTS.md`](FLAKY_TESTS.md).
Like `./profile`, it is report-only.
See `./flaky --help` for flags (`--suite-runs`, `--iterations`, `--device`/`--os`, `--no-update`, `--top`).

To download every artifact from a CircleCI job, pass its UUID or details URL to `./circleci-artifacts`.
It uses the authenticated CircleCI CLI and stores downloads under `.build/circleci-artifacts/` by default.
See `./circleci-artifacts --help` to choose another destination or open it in Finder after downloading.

Use `./snapshot-shards check` to validate the deterministic snapshot assignment.
Use `./snapshot-shards balance --junit PATH` to propose a new assignment from downloaded timing artifacts.
Pass several `--junit PATH` arguments to use median durations from several pipelines.
Use `./snapshot-shards balance --shards COUNT --junit PATH --write` to change the shard count.
Set the snapshot job `parallelism` to the planned count plus one intake worker.
The intake worker stops after checkout when it has no new suites.
New suites run on the intake worker until rebalancing adds them to the plan.
CI rejects a worker-count mismatch.
CI also rejects a snapshot worker that does not execute exactly its assigned suites.

The `./ide` script sets `core.hooksPath` to `.githooks`.
The pre-commit hook formats staged Swift with SwiftFormat and runs `./sync-agents --git-add`.
Generated Claude files stay in sync with `AGENTS.md`.

## Signing for on-device builds

The checked-in project has **no** development team.
Building to a simulator works for everyone.
Nothing machine-specific lands in Git.
To build to a physical device, supply your Apple Developer Team ID.

`Project.swift` reads it from the `TUIST_DEVELOPMENT_TEAM` environment variable.
When present, it stamps the value into the generated project as `DEVELOPMENT_TEAM`.
The value lives in `.mise.local.toml`, a local, **gitignored** mise config.
`mise exec -- tuist generate` (i.e. `./ide`) picks it up automatically.
Your team survives every regeneration.
When no team is set (CI, fresh clones), no `DEVELOPMENT_TEAM` is written.
Xcode behaves as before.

Set it once:

```bash
# Writes TUIST_DEVELOPMENT_TEAM to .mise.local.toml, then regenerates
./ide --team-id ABCDE12345
```

Find your Team ID in Xcode › Settings › Accounts (the "Team ID" column) or at [developer.apple.com/account](https://developer.apple.com/account) under Membership details.
You can also edit `.mise.local.toml` by hand:

```toml
[env]
TUIST_DEVELOPMENT_TEAM = "ABCDE12345"
```

## Project structure

```
Package.swift       Local Swift package (StuffCore, LifecycleKit, WhereCore, WhereUI, TestHostSupport, …)
Tools/Package.swift Independent macOS developer-command package (`stuff`)
BumperBowling.swift Executable Where architecture policy
.bumper/            Repo-owned Bumper shapes, rules, tests, and catalog
Project.swift       Tuist manifest (Where app, StuffTestHost, test bundles → SPM)
Tuist.swift         Tuist configuration
.mise.toml          Pins the Tuist, SwiftFormat, ShellCheck, and Ruby versions
.mise.local.toml    Local mise overrides, gitignored (e.g. TUIST_DEVELOPMENT_TEAM)
.swiftformat        SwiftFormat rules
.codex/             Codex managed-worktree setup, cleanup, and actions
.worktreeinclude    Ignored local files copied into Codex-managed worktrees
ide                 Dev script – bootstrap (mise + tools), hooks, sync-agents, tuist generate
swiftformat         Run SwiftFormat via mise (default: format `.`)
shellcheck          Lint every tracked shell script via pinned ShellCheck
sync-agents         Sync AGENTS.md → CLAUDE.md and .claude/skills/
simulator           Resolve/create this checkout's simulator, boot it, print its UDID
worktree            Check or safely fast-forward a checkout against origin/main
profile             Report build/test hot spots (see `./profile --help`)
flaky               Detect flaky tests, update FLAKY_TESTS.md (see `./flaky --help`)
circleci-artifacts   Download every artifact for a CircleCI job
snapshot-shards      Validate and rebalance snapshot suite assignments
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

The Where module bundles offline region polygons under [`Where/RegionKit/Sources/Resources/regions/`](Where/RegionKit/Sources/Resources/regions/).
US state boundaries come from [eric.clst.org/tech/usgeojson](https://eric.clst.org/tech/usgeojson/) (`gz_2010_us_040_00_5m.json`), converted from the [US Census Bureau Cartographic Boundary Files](https://www.census.gov/geographies/mapping-files/time-series/geo/cartographic-boundary.html).
US Government works are in the public domain.
See [`Where/RegionKit/README.md`](Where/RegionKit/README.md) for per-file provenance.

## License

Apache 2.0 – see [LICENSE](LICENSE).
