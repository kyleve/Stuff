# Adversarial Tooling Test Plan

This review is behavior-first: prove what each command does without requiring
the reviewer to judge whether its Bash, Python, or Ruby is idiomatic.

For every scenario, record five observable facts:

1. Command and environment.
2. Exit status.
3. Standard output.
4. Standard error.
5. Files, processes, devices, or applications changed.

A test passes because the command behaved correctly, not because its internal
functions returned expected values.

## Contract ledger

| Command | Supported environment | Reads | May mutate | Critical contract |
|---|---|---|---|---|
| `test` | macOS/Xcode, local + CI | manifests, artifacts | build directories | Streams progress and propagates failures |
| `profile` | macOS/Xcode | Xcode results | profiling workdir | Test/build failures abort; reporting failures do not |
| `flaky` | macOS/Xcode | Xcode results | `FLAKY_TESTS.md` | Test failures are data; build failures abort |
| `simulator` | macOS/Xcode | simctl, registry | owned simulators | Never deletes an unowned or wrong-runtime device |
| `icons` | mise Ruby | catalogs, manifest | tracked assets | All-or-nothing mutation |
| `Where/install` | macOS/Xcode/device | signing and device inventory | physical device | Dry run performs no build/install/launch |
| `Ledger/install` | macOS/Xcode | built/installed apps | `/Applications/Ledger.app` | Exact-process and transactional replacement |
| `tla-check` | macOS/Linux-compatible tooling | manifests/specs | retained run artifacts | Pinned tools and honest pass/fail policy |

Existing flags and their observable behavior are compared with `main`. New
behavior must be called out explicitly; the planned additions are the
mutating commands' `--dry-run` modes.

## Differential review against `main`

Run the old and new implementations against identical fake dependencies and
compare:

- Generated command arguments and environment.
- Output stream selection and ordering.
- Exit status.
- Resulting fixture filesystem.
- Recorded process and device operations.

Normalize only inherently variable values: temporary paths, timestamps, PIDs,
and durations. Required comparisons cover every help path, unknown options,
missing values, scope combinations, process-launch and child failures, TTY and
CI progress, empty and zero-test results, malformed external JSON, and
invocation from outside the repository.

For `test`, `profile`, and `flaky`, fake `xcodebuild`, `xcrun`, `swift`, and
`mise` feed captured logs and JSON into both versions. This proves parity
without requiring a real Xcode run for every policy branch.

## Adversarial scenarios

### Shell and interpreter boundary

Exercise every retained public wrapper with:

- macOS `/bin/bash` 3.2.
- Apple system Python 3.9.
- The pinned mise Ruby.
- A minimal `PATH`.
- `HOME` and `TMPDIR` redirected into temporary directories.
- Paths containing spaces and Unicode.
- `LC_ALL=C`.
- Interactive and non-interactive stdin and stdout.
- Invocation by absolute path from another working directory.

Verify that `--help` exits zero without external tools, devices, or network;
unknown or incomplete arguments fail before work; composable stdout stays
clean; child statuses are preserved; and interruption or a closed output pipe
does not leave a child process alive.

### `test`, `profile`, and `flaky`

Captured Xcode output and xcresult JSON cover:

- High-volume stdout and stderr.
- Split UTF-8 and unexpected bytes.
- Unknown xcresult node kinds.
- Nested suites and parameterized tests.
- Missing duration, result, and name fields.
- Truncated or malformed JSON.
- Xcode success with zero matching tests.
- Xcode failure without a result bundle.
- Reporting failure after a valid test run.
- Snapshot timing without a cached count.
- Cached tests without image counts.
- Stale cached totals that are exceeded.
- Partial flaky-suite and tight-loop results.
- Tests that always fail versus genuinely alternate pass and fail.

Policy invariants:

- `test`: any selected test failure or zero-test run fails.
- `profile`: build and test failures fail; a report parser failure warns and
  continues.
- `flaky`: test failures become observations; only infrastructure or build
  failure aborts.

### Simulator ownership

Fake `xcrun` and temporary registries cover:

- Same name on different runtimes.
- Duplicate same-name devices on one runtime.
- Missing, malformed, unwritable, and stale registry entries.
- A registered UDID renamed or moved to another runtime.
- An uninstalled runtime.
- Interrupted creation before registration.
- Failed registration after successful creation.
- Failed device and registry deletion.
- Active and abandoned locks.
- Concurrent first-time resolution from several processes.
- Lock-owner PID reuse or a malformed owner file.
- `--delete`, `--recreate`, and `--prune --dry-run`.

No destructive `simctl` call may occur unless checkout, registry entry, UDID,
name, and runtime all agree.

### Transactional mutations

Inject failures before any rename, after each rename, during rollback, during
backup cleanup, with a missing staged file, with symlinked targets or parents,
with an unreadable directory, across filesystems, with unknown manifest
metadata, and with malformed, truncated, or wrong-size PNGs.

After failure, exactly one state is legal:

- Everything remains byte-for-byte as it was; or
- The complete intended new state exists and cleanup failure is reported.

A mixture is never accepted.

### Installers

For `Where/install`, cover unset teams and malformed mise configuration;
empty, malformed, and schema-shifted `devicectl` JSON; mixed device families;
no, exact, and ambiguous matches; unusual names; confirmation EOF; list,
build, install, and launch failures; and a dry-run transcript with no project
generation, build, install, or launch.

For `Ledger/install`, cover missing, wrong-ID, symlinked, and malformed app
bundles; exact and similarly named processes; graceful and forced termination;
a surviving process; failures during build, copy, commit, rollback, and
cleanup; and a dry run with no build, signal, replacement, or launch.

Installer unit and command tests use temporary destinations. Public commands
that target `/Applications` or a physical device use dry-run or fake-process
paths unless a real operation is explicitly approved.

### TLA and generators

Cover manifest path traversal, missing modules and configurations, duplicate
cases, unknown expectations, TLC checksum mismatch, interrupted download,
missing Java or mise, translator and TLC statuses, absent expected-failure
text, source changes during execution, concurrent first-time cache population,
byte-identical region and attribution output, and output permission and disk
write failures.

## Mutation review

The suite must catch representative temporary mutations:

- Restore `rm_f` or `rm_rf` where failure must be visible.
- Change exact device matching to substring matching.
- Delete runtime validation.
- Make `--dry-run` perform one real operation.
- Drop `pipefail`.
- Convert a child failure to exit zero.
- Ignore malformed JSON.
- Remove rollback of the second icon catalog.
- Treat zero tests as success.
- Route simulator diagnostics to stdout.

Mutations are never committed. Record which test killed each mutation. A
surviving important mutation identifies a test gap.

## Real-environment smoke tests

After fixture tests pass, run the smallest real operations:

- `./simulator --no-boot`
- `./simulator --list`
- `./test StuffCoreTests`
- `./profile --tests-only --no-snapshots`
- `./flaky --suite-runs 1 --iterations 2 --no-update`
- Icon add and remove dry runs.
- `./Where/install --dry-run`
- `./Ledger/install --dry-run --no-open`

Then run the repository's full macOS gate:

```bash
mise install
./ide --no-open
./swiftformat --lint
./shellcheck
./test --everything
mise exec -- tuist test Ledger-macOS-Tests --no-selective-testing -- \
  -destination 'platform=macOS'
```

CircleCI exercises the rebased stack tip in a clean VM, including non-TTY
progress and artifact handoff.

## Stack execution order

Add a test to the earliest PR that owns its behavior:

1. PR #283: ShellCheck, TLA, generators, and interpreter portability.
2. PR #284: Xcode reports, progress, and failure policies.
3. PR #288: simulator ownership, locking, and concurrency.
4. PR #287: transactions, icons, and installers.

After each layer, rebase the layers above it. The stack tip runs the complete
suite.

## Harness constraints

- Prefer temporary directories and tiny fake executables.
- Share a fixture helper only after three tests need it.
- Add no external testing dependencies.
- Name the production failure each test prevents.
- Simplify a harness that grows larger than the policy it tests.
- Keep real destructive operations out of automated tests.

## Acceptance criteria

The stack is ready only when:

- Public behavior matches `main`, except documented additions.
- All important mutations are caught.
- Every injected failure remains observable.
- Mutating commands leave no partial state.
- Simulator deletion always requires exact ownership.
- Dry runs produce no mutation.
- Apple Bash 3.2, system Python 3.9, and pinned Ruby all pass.
- Commands work from local and CI-style environments.
- Every rebased PR has fresh required checks.

## Mutation evidence

These mutations were applied locally, the named test failed, and the mutation
was removed before commit:

| Removed or weakened behavior | Test that killed the mutation |
|---|---|
| Treat a successful Xcode run with zero tests as success | `test_test_rejects_a_successful_xcode_run_that_matched_zero_tests` |
| Replace the `xcodebuild` pipeline status with zero | `test_test_preserves_xcode_failure_through_the_progress_pipeline` |
| Ignore a failed `tee` or progress stage after successful Xcode | `test_test_surfaces_a_progress_process_failure_after_xcode_succeeds` |
| Trust a schema-shifted xcresult root instead of validating it | `test_tolerates_unknown_nodes_parameterized_names_and_missing_fields` |
| Match simulator names by substring | `test_near_match_name_never_counts_as_owned_or_claimable` |
| Flatten runtimes before validating a registered simulator | `test_rejects_registry_metadata_or_runtime_drift` |
| Let `--prune --dry-run` execute `simctl delete` | `test_prune_dry_run_and_delete_use_the_exact_registered_target` |
| Replace observable registry removal with `FileUtils.rm_f` | `test_forget_ignores_a_missing_entry_but_surfaces_removal_failures` |
| Reclaim an ownerless simulator lock after only five seconds | `test_ownerless_lock_inside_initialization_horizon_is_never_stolen` |
