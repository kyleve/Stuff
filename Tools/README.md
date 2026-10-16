# Stuff Tools

## Python and web lint

Run `mise install` and `mise exec -- npm ci` after a tool-pin change.
Run `mise exec -- npm run lint` for Python, TypeScript, Astro, and CSS correctness checks.
Run `mise exec -- npm run test:lint` to verify the lint rules against invalid fixtures.
The checks cover repository Python and both web projects. Type-aware ESLint also checks TypeScript tests.
Ruff targets the supported Python 3.9 command environment. Run `mise exec -- npm run format:python` to format Python files.
The shared lint command checks formatting without changing files. Keep formatting changes in separate commits.
CSS uses the standard Stylelint preset. The configuration preserves three Safari-prefixed properties without disabling the prefix rule.
The standard duplicate-property rule permits different CSS syntaxes, but rejects repeated declarations with different values in the same syntax.

## Daily Flyover publication

`.github/flyover-apps.json` owns hosted capture registration. `flyover_apps.py` validates it before capture.
`flyover_ci.py` captures all registered apps serially. `flyover_bundle.py` validates the ZIP transport and captured identities.
`flyover_distribution.py` requests CircleCI capture and publishes a complete bundle as an immutable prerelease asset.
`flyover_pages.py` includes the latest bundle in the existing install-site deployment.
`circleci_pipeline.py` owns shared CircleCI transport. Installer-specific IPA policy remains in `InstallerKit`.
Pipeline and workflow discovery retry HTTP 404 responses within the existing polling deadline.
The client closes discarded HTTP error responses before each retry.
Other HTTP failures propagate immediately, including missing jobs or artifacts.

The daily controller uses the existing `INSTALLER_CIRCLECI_PROJECT`, `INSTALLER_CIRCLECI_PIPELINE`, and `INSTALLER_CIRCLECI_TOKEN` configuration.
The names remain compatible with the existing installation setup. Flyover does not use its signing context.
Publication validates and versions every declared thumbnail size, including the optional `thumbnailVariants` records.
See [Flyover publication](../Shared/Flyover/README.md#daily-web-publication) for URLs, scheduling, and recovery behavior.
`flyover_retention.py` removes expired release bundles after successful Pages deployment.
It keeps seven days of releases, the deployed bundle, and the newest published bundle.
Cleanup failures fail the workflow without rolling back the deployed site. Git tags remain unchanged.

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
The profiler and CI JUnit export use precise execution durations from `xcode_results.py`.
Parameterized tests retain one test identity and sum their argument and repetition durations.
These sums measure elapsed test work. Concurrent executions can overlap, so the sum is not the suite wall time.
The progress report counts completed test functions, including named tests and tests with expected issues.
Skipped functions and parameter arguments do not add separate completion counts.
`flyover_cli.py` parses the public Flyover commands and reports exit status.
`flyover_png.py` validates PNG dimensions, chunk checksums, scanline filters, and the complete compressed stream before publication.
It accepts native non-interlaced grayscale and RGB captures, with optional alpha, at 8 or 16 bits per channel.
Other encodings fail explicitly. Each image is limited to 128 MiB encoded and 512 MiB expanded.
Validation does not reconstruct colors or interpret ancillary metadata. Native captures remain unchanged.
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
with rollback to the icon catalogs. The icon and physical-device selection
policies are likewise tested with temporary catalogs and captured command
output rather than tracked assets or devices.

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

