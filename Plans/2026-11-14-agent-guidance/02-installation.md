# External skill layout repair

Status: ready
Dependencies: [01](01-guidance.md)
Requirements: R-03; exclusions X-01 through X-04 from the [overview](README.md).

## Contracts and flow

Read the root repository contract, the Tools contract for command changes, and the guidance-authoring contract.
Use planning, skill-creator, simple-english, running-tests, code-review, and github-workflow as applicable.
Canonical instructions produce generated mirrors. The validator reads those inputs and returns diagnostics and an exit status.
External installation flows from the pinned package through exclusions and validation to staged FileTransaction replacement, then mirror synchronization.
No Swift API, actor, or app ownership changes are part of this deliverable.

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

## Recovery

Use the relocation map for incomplete documentation moves. Keep work on the feature branch.
Installer failures must retain the prior installation; preserve transaction recovery material if rollback fails.
Resume from the recorded pending step and repeat only invalidated checks.

## Progress

- [ ] Implement the steps.
- [ ] Verify acceptance and record evidence.
- [ ] Review and publish the deliverable.

## Execution record

2026-11-14: approved plan recorded; execution authorized by the user.

## Resume point

Complete the steps above in dependency order. Publication and evidence remain pending.
