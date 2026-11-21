# 01 — Safe local selection

- Status: executing
- Depends on: None
- Shared context: [Overview](README.md)

## Deliverable

Implement R-01 through R-03 under exclusions X-01 through X-04.
Keep selection policy importable and the public command responsible for execution.
Follow [Tools/AGENTS.md](../../Tools/AGENTS.md), the root contract, and running-tests.
Existing guards are `test_test_runner.py`, `test_grouped_tests.py`, and `test_xcode_command_contracts.py`.

## Design and steps

1. Parse all literal source/resource roots and target/product relationships. Add explicit ownership for generated inputs.
2. Collect NUL-delimited Git changes, including deletions, both rename sides, local changes, and untracked files.
3. Resolve every owner and reverse dependency. Use full selection for uncertain inputs; reject unsupported graph syntax with an actionable error.
4. Add a public preview with text and JSON reports. Share the decision with normal execution.
5. Update Tools documentation and add direct-policy and public-command regression coverage.

The overview owns the data flow. No Swift types change.
Use `./test --dry-run [--json] [--base REF] [--head REF]` for affected selection.
`--head` is preview-only and excludes local changes so historical diffs remain reproducible.
Both preview and execution call the same Python policy. The report contains reasons, changed paths, selected/skipped logical bundles, and host-check scope.
Parse balanced target declarations and literal source/resource arrays. Reject unsupported expressions instead of borrowing the next declaration.
Unknown paths and unavailable Git history select all known bundles and host macros. Unsupported graph syntax stops with an explicit-scope recovery command.

## Acceptance and verification

- Shared fixtures select ordinary and snapshot owners; host changes select all hosted consumers.
- Site and generator changes select the generated snapshot bundle.
- Rename, deletion, spaces, missing history, unknown files, and manifest changes cannot cause a silent empty selection.
- A preview runs no test, build, simulator, or generation commands; malformed flags fail before those effects.
- Grouped selectors retain their existing logical-to-physical translation.
- Run affected Python contract tests, repository lint, shellcheck, and the checks selected under running-tests.

## Recovery and progress

No production state changes. Inspect the diff and rerun failed checks before resuming.
Implementation and checks are complete. Publication is pending.

## Execution record

Verified 2026-11-21 against base `ddb0a8546` and the working implementation:

- `python3 -m unittest Tools.Tests.test_test_selection Tools.Tests.test_test_runner Tools.Tests.test_grouped_tests Tools.Tests.test_xcode_command_contracts`: 58 passed.
- `mise exec -- npm run lint`: passed. `./shellcheck`: passed. `git diff --check`: passed.
- `./test CreditKitTests --no-generate`: 11 simulator tests passed on iPhone 17 / iOS 27.2. Build succeeded in 50.230 seconds; test phase took 12.908 seconds. These are smoke-run measurements, not comparative savings.
- Normal architecture checks passed: 30 rule tests and no architecture violations. Flyover command checks, attribution (1 run, 3 assertions), and backup upgrader (16 runs, 58 assertions) passed.
- The preceding `./test CreditKitTests` generated the project successfully. Its execution overlapped a wrapper edit, so its simulator result was discarded and the stable wrapper was rerun.
- The grouped scanner needed compiler-cache access outside the filesystem sandbox. The final 58-test run used that access and passed.

Independent review reproduced and resolved four parser/ownership defects: a broad installer path included app build scripts; a qualified helper return type lost host links; computed product names matched a literal prefix; nonempty helper defaults lost dependencies. New regressions cover these cases. Full fallback also retains main's grouped full scheme.

The final review found no remaining actionable issues. No Swift behavior or snapshot references changed; full app and image suites were not run.
Resume: commit and publish 01, then finalize the PR experiment with the published implementation revision.
