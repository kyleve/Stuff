# External skill layout repair

Status: complete
Dependencies: [01](01-guidance.md)
Requirements: R-03; exclusions X-01 through X-04 from the [overview](README.md).

Read the [shared contracts and recovery](README.md#shared-contracts-and-recovery) for this deliverable.

## Steps

1. Add optional manifest `exclude` paths and configure Swift Testing's nested `skills` and `.claude-plugin` directories.
2. Share source/layout validation across add, install, and update operations.
3. Repair invalid existing layouts at their pinned revisions. Stage and validate before FileTransaction replacement.
4. Test fresh installation, repair, idempotency, invalid inputs, and failure recovery; regenerate attribution and mirrors.

## Acceptance and verification

Run focused Ruby installer tests and public-command contracts with fake repositories and temporary directories.
Verify failed fetch, copy, or replacement leaves the prior skill intact.
Run the real pinned install; verify exactly one Swift Testing entry point and repeat installation without changes.
Run `./attribution` and `./attribution --check`.

## Progress

- [x] Implement the steps.
- [x] Verify acceptance and record evidence.
- [x] Review and publish the deliverable.

## Execution record

2026-11-14: approved plan recorded; execution authorized by the user.

2026-11-14: implemented shared metadata/layout validation, explicit exclusions, pinned repair, and staged directory/manifest replacement.
The real pinned package contained a symlink inside its excluded plugin tree. Exclusions now prevent traversal and copying of that tree.
Symlinks outside exclusions remain rejected. Regression fixtures cover both cases.
Focused installer, orchestration, command, and transaction checks passed: 24 tests and 163 assertions before the final added outside-target assertion.
Public command contracts passed separately: 2 tests and 130 assertions outside the sandbox.
The sandbox run hit unrelated Xcode diagnostics from snapshot-shards help.
The real install retained Swift Testing revision `2d6bba14a3c8bf3694f218b92fffe617c41ae43e` and produced one entry point in each source/mirror tree.
A second install emitted no changes. Attribution regeneration and its offline check passed; the report remained unchanged.
Independent review will cover the complete tooling change with deliverable 03.

2026-11-14: the complete branch review is now recorded in deliverable 03. No installer findings remain.
Implementation and verification are complete; publication is the remaining blocker.

2026-11-14 publication: the user explicitly approved public publication. The reviewed branch is published in [PR #499](https://github.com/kyleve/Stuff/pull/499), ready for review.

## Resume point

Implementation is delivered. Continue any PR feedback through github-workflow. Linear linking remains unavailable without credentials.
