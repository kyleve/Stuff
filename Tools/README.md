# Stuff Tools

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
Filesystem-heavy Ruby generators are require-safe so their behavior can be
exercised against temporary repositories. `SimulatorRegistry` validates exact
runtime ownership from captured `simctl` JSON and persists private claims
atomically; its command-level tests replace `xcrun` rather than touching a
developer's devices. `FileTransaction` supplies staged multi-path replacement
with rollback to the icon catalogs and Ledger installer. The icon, physical
device-selection, and app-install policies are likewise tested with temporary
catalogs and captured command output rather than tracked assets, devices, or
`/Applications`.

`where_signing.py` validates Where's ad hoc profiles and generates export settings.
`Where/archive` owns the Xcode processes.
`installer_distribution.py` selects `main` and labeled PR channels, then checks the live GitHub state before publication or retirement.
Its trusted controller fails PR builds with merge conflicts and permits page retirement regardless of conflicts.
`github_releases.py` uploads an IPA to a draft, verifies its digest and size, and publishes it without replacing existing assets.
`github_api.py` rejects credential-bearing redirects.
`installer_update_feed.py` publishes the Pages catalog from successful distribution receipts.
It preserves concurrent apps and channels, bounds retained build history, and identifies rewritten commit history.
`installer_installation.py` owns exact-build URLs and OTA manifests.
`installer_update_site.py` validates the catalog and stages install pages, artwork, manifests, and JSON as one Pages artifact.
`installer_apps.py` loads trusted app registrations, including optional site artwork and subtitles.
`installer_site.css` owns the responsive catalog and build-page styles, with light and dark appearances.
Build pages show signed version metadata, download size, publication time, source links, and incoming commits.
Their tests use temporary profiles, fake processes, and captured API responses.
See [the installer guide](INSTALLER.md) for app registration and shared publication.
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

```bash
python3 -m unittest discover -s Tools/Tests -p 'test_*.py'
mise exec -- ruby -I Tools/Tests -e 'Dir["Tools/Tests/**/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
```

Tests must not require Xcode, Java/TLC, networking, or the developer's real
repository state. Add shared fixtures under `Tools/Tests/Fixtures`; otherwise
create the smallest useful input in the test's temporary directory.

[`ADVERSARIAL_TEST_PLAN.md`](ADVERSARIAL_TEST_PLAN.md) records the public
behavior contracts, portability matrix, destructive-operation boundaries, and
mutation review used to accept changes to these tools.
