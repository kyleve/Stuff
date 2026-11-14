# Offline guidance validation and CI

Status: ready
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

- [ ] Implement the steps.
- [ ] Verify acceptance and record evidence.
- [ ] Review and publish the deliverable.

## Execution record

2026-11-14: approved plan recorded; execution authorized by the user.

## Resume point

Complete the steps above in dependency order. Publication and evidence remain pending.
