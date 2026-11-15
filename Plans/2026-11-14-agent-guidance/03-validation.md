# Offline guidance validation and CI

Status: complete
Dependencies: [01](01-guidance.md), [02](02-installation.md)
Requirements: R-04; exclusions X-01 through X-04 from the [overview](README.md).

## Contracts and flow

Read the root repository contract, the Tools contract for command changes, and the guidance-authoring contract.
Use planning, skill-creator, simple-english, running-tests, code-review, and github-workflow as applicable.
Canonical instructions produce generated mirrors. The validator reads those inputs and returns diagnostics and an exit status.
External installation flows from the pinned package through exclusions and validation to staged FileTransaction replacement, then mirror synchronization.
No Swift API, actor, or app ownership changes are part of this deliverable.

## Steps

1. Add an importable Ruby validator and the read-only `./sync-agents --check` command.
2. Validate byte budgets, overrides, frontmatter, unique names, canonical entry points, local links, and present mirrors.
3. Allow absent external skills and absent generated mirrors on clean CI checkouts; report that coverage distinction.
4. Run validation after Linux classification and in the existing required lint job, preserving successful documentation shortcuts.
5. Add boundary, parser, discovery, command, and CI regression tests. Review the complete branch and publish.

## Acceptance and verification

Test exact byte boundaries, UTF-8, combined chains, override precedence, duplicate/nested skills, and malformed frontmatter.
Test local paths and anchors, fenced examples, mirrored links, absent external skills, and read-only command behavior.
Test valid documentation-only selection and invalid guidance propagation to the required lint job.
Run the checker, focused Ruby suites, Python CI regression suites, and affected linters.
Review the complete diff through code-review, including its required independent static review.

## Recovery

Use the relocation map for incomplete documentation moves. Keep work on the feature branch.
Installer failures must retain the prior installation; preserve transaction recovery material if rollback fails.
Resume from the recorded pending step and repeat only invalidated checks.

## Progress

- [x] Implement the steps.
- [x] Verify acceptance and record evidence.
- [x] Review and publish the deliverable.

## Execution record

2026-11-14: approved plan recorded; execution authorized by the user.

2026-11-14: implemented the validator, Markdown checks, hidden-directory synchronization, and both CI invocations.
The checker found seven relocated links that failed from the Claude mirror. Their targets now route through the repository root.
Boundary tests caught and corrected root omission from relative Pathname ancestor accounting.
Current focused checks pass: 33 tests, 215 assertions. Final checks and independent static review remain in progress.
The Linux action's Ruby-only setup uses the documented `install_args` input from [mise-action v3](https://github.com/jdx/mise-action/blob/v3/action.yml).

2026-11-14 final verification:

- `mise exec ruby -- ./sync-agents --check`: passed; 57 instruction files, 12 owned skills, largest chain 27,801/28,672 bytes.
- Ruby guidance, installer, synchronization, command, and FileTransaction suites: 43 tests, 278 assertions, all passed.
- Public command contracts: 2 tests, 130 assertions, passed outside the sandbox because snapshot-shards help emits unrelated Xcode diagnostics inside it.
- Python CI classifier, CircleCI selection, and GitHub workflow suites: 33 tests, all passed.
- Ruff lint and format checks for the changed Python test, attribution check, and `git diff --check`: passed.
- Native builds, image snapshots, and SwiftFormat were omitted because no Swift, UI, or native build inputs changed. Hosted CI and live model evaluations were not run.

Fresh static review covered baseline `b629d56ac` through commits `2df3ec197` and `635682573`, plus the full deliverable-03 working tree.
It covered installation transactions, discovery, Markdown parsing, command boundaries, CI, tests, and required-read routes.
Text comparisons found no lost invariant bullets in the major relocated contracts. This does not establish live model activation.

The reviewer reproduced three defects. Empty Markdown destinations raised an exception; they now resolve to the current document.
Ignored instructions could acquire generated mirrors that the checker rejected; sync and check now share the Git inventory.
An unqualified mise invocation could install unrelated tools; both CI checks now use `mise exec ruby --`.
Each correction has regression coverage. Re-review and the repeated affected checks found no remaining actionable findings.

2026-11-14 publication: the user explicitly approved public publication. The reviewed branch is published in [PR #499](https://github.com/kyleve/Stuff/pull/499), ready for review.

## Resume point

Implementation is delivered. Continue any PR feedback through github-workflow. Linear linking remains unavailable without credentials.

After integrating `main` at `2e27fc5ba`, the 43 Ruby tests, 33 Python CI tests, and repository guidance check passed again.
All Swift files, catalogs, and image references remain identical to that main revision. Native suites were not rerun for this documentation conflict resolution.
Independent merge review confirmed the new invariant appears exactly once, its required read route remains valid, and no unresolved conflicts or logical guidance conflicts remain.
