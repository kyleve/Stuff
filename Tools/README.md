# Stuff Tools

## Daily Flyover publication

`.github/flyover-apps.json` owns hosted capture registration. `flyover_apps.py` validates it before capture.
`flyover_ci.py` captures all registered apps serially. `flyover_bundle.py` validates the ZIP transport and captured identities.
`flyover_distribution.py` requests CircleCI capture and publishes a complete bundle as an immutable prerelease asset.
`flyover_pages.py` includes the latest bundle in the existing install-site deployment.
`circleci_pipeline.py` owns shared CircleCI transport. Installer-specific IPA policy remains in `InstallerKit`.

The daily controller uses the existing `INSTALLER_CIRCLECI_PROJECT`, `INSTALLER_CIRCLECI_PIPELINE`, and `INSTALLER_CIRCLECI_TOKEN` configuration.
The names remain compatible with the existing installation setup. Flyover does not use its signing context.
See [Flyover publication](../Shared/Flyover/README.md#daily-web-publication) for URLs, scheduling, and recovery behavior.

This directory contains importable implementations and direct tests for the
repository's retained Python and Ruby developer tooling. Public commands stay
at their established paths in the repository root; shell launchers own public
argument handling, process orchestration, and bootstrap, while structured
parsing and reporting policy live here.

[`AGENTS.md`](AGENTS.md) owns the maintenance rules for these implementations
and their public wrappers. It covers failure propagation, transactional
replacement, simulator ownership, and validation at the command boundary.

The existing CircleCI artifact, JUnit, and snapshot-shard helpers remain Python
because they are already integrated and directly tested. `tla_check.py`
similarly owns TLA+ manifest validation, isolated translation, TLC argv, and
result reporting without requiring Java in its tests. The Xcode-facing root
commands keep process and simulator orchestration in shell; `xcode_results.py`
shares xcresult traversal, `snapshot_reports.py` shares capture reports, and
the command-specific Python modules retain each command's distinct policy.
`flyover_cli.py` parses the public Flyover commands and reports exit status.
`flyover_export.py` composes build metadata, hosted capture, artifact validation, and publication.
`flyover_publication.py` owns staging, destination checks, replacement, and recovery for one generated directory.
`flyover_manifest.py` validates artifact files and builds their allowlists.
The pure `flyover_schema.py`, `flyover_canvas.py`, and `flyover_images.py` validators check catalog references, geometry, and image coverage.
`flyover_schema_values.py` supplies their primitive checks.
`flyover_artifact_access.py` opens validated files without following replacement links.
`flyover_site.py` builds the viewer and runs Astro against an isolated copy.
Both websites share the root npm workspace and `astro_site.py` launcher.

Flyover publication uses two directory renames, not an atomic exchange.
Before installation, a failure restores the previous atlas only if the destination is absent.
After installation, cleanup never removes the new atlas.
If recovery fails or another destination appears, the command retains the backup and reports its path with the original error.
SIGINT and SIGTERM return 130 and 143 after successful recovery. Recovery errors return 1 with diagnostics.
SIGKILL and power loss do not guarantee automatic recovery.

Filesystem-heavy Ruby generators are require-safe so their behavior can be
exercised against temporary repositories. `SimulatorRegistry` validates exact
runtime ownership from captured `simctl` JSON and persists private claims
atomically; its command-level tests replace `xcrun` rather than touching a
developer's devices. `FileTransaction` supplies staged multi-path replacement
with rollback to the icon catalogs and Ledger installer. The icon, physical
device-selection, and app-install policies are likewise tested with temporary
catalogs and captured command output rather than tracked assets, devices, or
`/Applications`.

`InstallerKit/signing_profiles.py` validates registered apps' ad hoc profiles and generates export settings.
`repository.repository_root` (Python) and `Repository.root` in `repository.rb` (Ruby) find a tool's checkout through its nearest `.git` directory or worktree file.
Use it for checkout-relative resources instead of fixed parent-directory counts.
`./signing` calls the shared Fastlane workflow for local maintenance and read-only archives.
`./signing setup --app <id>` checks merged registrations, refreshes profiles, and enables the app's distribution variable.
Add `--pr <number>` to prepare a temporary PR checkout and request publication after setup.
Setup uses the conventional local API-key JSON path and prompts privately for a missing Match password.
Use `--dry-run` to check registration and PR eligibility without changing signing assets or GitHub state.
`Where/archive` is its Where-specific convenience wrapper.
`Gemfile.lock` pins Fastlane and its transitive dependencies, isolated in ignored `vendor/bundle/`. Run `./ide --install --no-open` to install them.
[`InstallerKit/`](InstallerKit/README.md) owns shared app registration, publication, build stamping, and install-site generation.
Its private Python modules use qualified imports under `Tools.InstallerKit`.
Run their commands from the repository root with `python3 -m Tools.InstallerKit.<module>`.
Tests use the same module imports without changing Python's search path.
The [Astro project](InstallerKit/Site/README.md) owns routes, components, and styles.
[Where's distribution guide](../Where/DISTRIBUTION.md) owns its signing setup and device validation.

## Snapshot shard policy

`snapshot_shards.py` keeps weekly assignments stable. Its bounded greedy search
places intake first, then stops existing-suite moves at a 5% reduction in the
slowest worker. If single-suite moves cannot reach that target, it discards them.
It does not search swaps or claim a globally minimal number of moves.
Explicit shard-count changes retain full longest-processing-time balancing.
The balance command emits a JSON report on stdout and diagnostics on stderr;
only version and assignments are persisted. Legacy plans containing timing
metadata remain readable. No-op writes preserve their original bytes.
The [rebalance skill](../.agents/skills/rebalance-snapshot-shards/SKILL.md)
owns sample selection and publication.

## Testing

Install the site dependencies before the retained installer tests or snapshot builds:

```bash
mise exec -- npm ci
```

```bash
python3 -m unittest discover -s Tools/Tests -p 'test_*.py'
mise exec -- ruby -I Tools/Tests -e 'Dir["Tools/Tests/**/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
```

These Python and Ruby tests must not require Xcode, Java/TLC, networking, or the developer's real
repository state. Add shared fixtures under `Tools/Tests/Fixtures`; otherwise
create the smallest useful input in the test's temporary directory.

The install site's image tests run on the pinned iOS simulator:

```bash
./test ToolsSnapshotTests --review
```

Each build runs [the fixture generator](Tests/Fixtures/installer_update_site_snapshots.py)
against the production Astro build. The bundle loads those pages in offline
`WKWebView` instances through `SnapshotKitTesting.assertHTMLSnapshots`.
The generator inlines the emitted CSS and artwork for offline capture.
References cover the main-build homepage, app PR pages, release details, unavailable commit history,
retired channels, an empty catalog, and missing artwork and metadata on iPhone and iPad in both appearances.
They use the existing LFS references, snapshot scheme, and CI shard discovery.

[`ADVERSARIAL_TEST_PLAN.md`](ADVERSARIAL_TEST_PLAN.md) records the public
behavior contracts, portability matrix, destructive-operation boundaries, and
mutation review used to accept changes to these tools.
