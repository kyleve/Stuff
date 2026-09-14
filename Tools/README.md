# Stuff Tools

This directory contains importable implementations and direct tests for the
repository's retained Python and Ruby developer tooling. Public commands stay
at their established paths in the repository root; shell launchers own public
argument handling, process orchestration, and bootstrap, while structured
parsing and reporting policy live here.

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

`porthole_compiler_contract.py` builds original and instrumented application source with matching compiler settings.
It checks the pinned Xcode and actual compiler commands for every adopting module.
The six CI pairs cover all Where configurations with simulator and iPhoneOS SDKs.
Fresh product directories prevent cached compilation from passing as new evidence.
The helper preserves logs and a result document after failure. Its hermetic tests substitute command execution.
It rejects extension-unsafe compiler or linker diagnostics in both build streams, even when the build exits successfully.
The bounded scan fails on missing logs, files larger than one GiB, or lines larger than four MiB.

After both builds, the helper runs `porthole_packaging.py` on each completed app and preserves its JSON report.
The checker verifies one app-embedded shared image, host dependency resolution, seven sampled metadata families, and required resource copies.
It checks app-owned intent and shortcut identifiers and rejects extension/framework metadata or standalone Porthole catalog resources.
The pair compares complete app metadata after normalizing only the two Year parameters' accepted input-type ordering.
It also compares resource paths and hashes, excluding only `WhereAssets/Assets.car` payload bytes, which contain compiler timestamps.
The checker preserves raw hashes and requires identical app/extension copies within each product.
Required asset paths, nonempty payloads, and current source manifests remain checked. Compiled rendition equivalence requires separate asset or runtime validation.
A failed packaging check fails the compiler pair.

`porthole_macho_symbols.py` reads bounded arm64 nlist records. `porthole_macho_exports.py` looks up a finite set of export-trie names.
These readers use public Mach-O layouts. They avoid expanding the whole trie or invoking `nm` on large Swift images.
The checker uses `otool` only for load commands. Hermetic tests substitute that command boundary and create small synthetic images.
It measures the relocatable app dependency closure, not in-place dyld search inside a Mac build directory.
For an exact `Build/Products/<configuration>-<sdk>/Where.app` input, it excludes and reports only that product directory's absolute `PackageFrameworks` runpath.
Every dependency still needs an in-app fallback. Direct outside dependencies, other outside runpaths, escaping symlinks, and duplicate metadata remain failures.
This exception does not establish simulator dyld behavior or physical-device execution.

Run the checker on an existing product without building or launching it:

```bash
python3 Tools/porthole_packaging.py --app /path/to/Where.app --repository . \
  --configuration Release --sdk iphoneos --output /path/to/new-packaging-report.json
```

The CI compiler-pair matrix uploads both packaging reports. Resource and intent rules are shared across Debug, Beta, Release, and both iOS SDKs.
The checker verifies direct app/extension resource paths; debugger test environment overrides cannot satisfy these checks.
Update its expected routes and resource rules with intentional product changes. Preserve explicit failures for unexpected platform or toolchain output.
Static checks do not qualify runtime bundle loading, widget/share interaction, Siri/Shortcuts execution, signing, distribution, or device performance.
Asset-catalog internals and timestamp-bearing App Intents NLU artifacts remain outside this check.

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
