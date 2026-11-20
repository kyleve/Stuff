# Development environments and CI

## Codex worktree specific instructions

[`.codex/environments/environment.toml`](../../.codex/environments/environment.toml)
owns setup, cleanup, and toolbar actions for Codex-managed worktrees. Keep it
idempotent. Regenerate it through the ChatGPT desktop app's local environment
editor when changing its schema.

- macOS setup runs `./ide --bootstrap --no-open`. Bootstrap trusts the new
  checkout's `.mise.toml`, installs pinned tools, hydrates every Git LFS object
  referenced by the checkout, syncs agent files, and generates without opening
  Xcode.
- Linux setup delegates to [`Tools/setup-linux.sh`](../../Tools/setup-linux.sh). It has the
  same platform limits documented below.
- Setup first runs `./worktree --check-main`, which refreshes `origin/main` and
  warns without moving `HEAD` when the selected checkout does not contain it.
  An unavailable remote warns without blocking setup.
- The **Update to latest main** action runs `./worktree --update-main`. It only
  fast-forwards a checkout directly behind `origin/main`. It refuses divergent
  history.
- [`.worktreeinclude`](../../.worktreeinclude) copies only ignored machine-local files
  required by a new managed worktree. `AGENTS.override.md` is copied by Codex
  automatically and must not be listed there.
- Cleanup uses `./worktree --cleanup` for that checkout's DerivedData and
  registered simulator. Use `--dry-run` to preview both actions.
- `./worktree --prune-derived-data --dry-run` previews cache removal for deleted
  Codex worktrees. [Tools/AGENTS.md](../../Tools/AGENTS.md) owns cache ownership rules.

## Linux cloud instructions

Cloud agent VMs run **Linux**, not macOS. This repo targets **iOS 27** with
**Xcode 27+** and **Tuist** (macOS-only). Treat Linux as a partial dev
environment. Formatting and agent sync work on Linux. Builds, tests, and running the
**Where** app require macOS (as in CI on the `xcode-27` runner image).

### Setup is committed

[`Tools/setup-linux.sh`](../../Tools/setup-linux.sh) is the shared Linux bootstrap.
The Codex environment runs it after checkout. Other Linux environments can run it from the repository root.
It installs `mise`, trusts the config, installs pinned tools and site dependencies, and configures Git LFS and hooks.
Setup remains idempotent for cached environments.

`git-lfs` is required on both platforms. The `.githooks/` LFS hooks fail when the binary is absent.
Both bootstraps install it before setting `core.hooksPath`.

### What works on Linux

**Tuist is scoped to `os = ["macos"]`** in `.mise.toml`. Mise skips an
OS-restricted tool entirely rather than failing on it. `mise install` and
every `mise exec --` now succeed here instead of dying on `unsupported env:
linux/amd64`. `mise install` also fires the `postinstall` hook that fetches the
external agent skills. Those skills are gitignored and absent from a bare checkout.

| Check | Command |
|-------|---------|
| Install the pinned tools | `mise install` (skips Tuist) |
| Website type checks | `mise exec -- npm run check --workspaces --if-present` (install dependencies first) |
| SwiftFormat lint | `./swiftformat --lint` |
| Shell lint | `./shellcheck` |
| Attribution drift | `./attribution --check` |
| Retained Python tool tests | `python3 -m unittest discover -s Tools/Tests -p 'test_*.py'` |
| Agent file sync | `mise exec -- ./sync-agents` (or `--install`) |
| Git LFS | `apt-get install git-lfs` — required by `.githooks/` |
| Pre-commit hook | works — `mise exec --` no longer pulls in Tuist |

These commands cover much of CI's `format` job. Three portability carve-outs remain filed together in
the [Linear backlog](../../BACKLOG.md). They have distinct causes. One Python
contract test pins macOS bash's `126` exit status for an unlaunchable command
and reports `127` here. The Ruby retained-tool tests run each command under a
hermetic `PATH=/usr/bin:/bin`, which resolves a `#!/usr/bin/env ruby` script
only where the OS ships a system Ruby. And `sync-agents` is itself
`#!/usr/bin/env ruby`, so it needs the `mise exec --` prefix above, where
`attribution` wraps that for you. None is a defect in the command under test.

### What does not work on Linux

- **Tuist** — `tuist test`, `tuist build`, and `./ide` (which generates the
  Xcode project)
- iOS Simulator, and running the **Where** app
- **Anything needing a Swift toolchain** — the VM ships none, so `swift run
  bumper` (the architecture lint) and `./xcstrings` (a `#!/usr/bin/swift`
  script) both fail here even though neither needs Xcode. Diagnostic signature
  for the latter: ``mise ERROR "./xcstrings" couldn't exec process: No such file
  or directory``.
- Anything else needing Xcode

These are limits of the **VM**, not of cloud agents generally. A remote-control
session runs iOS. Anything that needs the app actually running — reproducing
a bug, checking a screen, exercising a flow by hand — goes there rather than
being written off as untestable from a cloud agent.

### Full build & test (macOS only)

**CI runs on two systems.** GitHub Actions
([`.github/workflows/ci.yml`](../../.github/workflows/ci.yml)) separates lint, tool tests, and web tests:

- `format` (**Lint & Formatting**) runs language linters, formatting checks, lint-rule tests, symbol and catalog checks, and attribution validation.
- `test-tools` (**Tool Tests**) runs the Python and Ruby tool suites, CircleCI helper tests, and snapshot-plan validation.
- `test-web` (**Web Checks & Tests**) runs Astro/TypeScript checks, web unit tests, and Flyover browser regressions.
- `architecture` (**Bumper Bowling**) and `test-macos` (**Build & Test (macOS)**) retain their separate checks.

Require the three split job statuses directly in main’s branch protection.
The `test-macos` job installs the shared web dependencies before the host tests.
It runs the Flyover, attribution, backup-upgrader, and macro tests.
These required GitHub jobs run alongside the CircleCI builder. CircleCI
([`.circleci/config.yml`](../../.circleci/config.yml)) selects work on Linux, then
continues through [`.circleci/continue.yml`](../../.circleci/continue.yml). Full CI builds `build-ios-tests` once
and attaches its products to `test-ios` and the sharded `snapshot` job,
plus two build-only shards for **Where Beta** and **Where App Store**. The iOS
tests moved there in PR #237 and gained the build handoff in PR #276. CircleCI
passes `--skip-architecture` and `--skip-host-tests` because GitHub owns those checks.
Do not read one configuration as the whole of CI. Documentation-only PRs retain required check names and skip expensive jobs.
PRs with `NO-CI` in their title skip both CI systems.
Use this marker only for prototypes and exploratory work. The marker does not
skip pushes to `main` or manual CircleCI full-gate runs. See the
[`running-tests`](../skills/running-tests/SKILL.md) skill for simulator
setup and the full validation recipe.

The separate [app distribution workflow](../../.github/workflows/installer-distribution.yml)
requests signed device archives on CircleCI and publishes them through GitHub Releases and Pages when enabled.
Its `installable` label is independent of the test workflows' `NO-CI` title marker.

The [daily Flyover workflow](../../.github/workflows/flyover-daily.yml) requests unsigned
simulator captures on CircleCI. `.github/flyover-apps.json` registers each app's
hosted test. The existing Pages publisher includes the latest validated bundle
under `/flyover/`, alongside the install site.
