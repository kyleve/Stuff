# Guidance restructuring

Status: complete
Dependencies: None
Requirements: R-01, R-02; exclusions X-01 through X-04 from the [overview](README.md).

## Contracts and flow

Read the root repository contract, the Tools contract for command changes, and the guidance-authoring contract.
Use planning, skill-creator, simple-english, running-tests, code-review, and github-workflow as applicable.
Canonical instructions produce generated mirrors. The validator reads those inputs and returns diagnostics and an exit status.
External installation flows from the pinned package through exclusions and validation to staged FileTransaction replacement, then mirror synchronization.
No Swift API, actor, or app ownership changes are part of this deliverable.

## Steps

1. Preserve full sections and bullets while moving task-specific contracts to scoped instructions or references.
2. Add explicit read conditions; update tracked links and both skill entry points.
3. Add the human prompting guide and guidance-authoring contract.
4. Verify the relocation map, budgets, references, and synchronized mirrors before committing.

## Acceptance and verification

Compare each recorded source section or bullet with its destination after resolving relative links.
Measure UTF-8 bytes for the root, every discovered chain, and every repo-owned skill entry point.
Run `mise exec -- ./sync-agents` and inspect the resulting source diff and generated mirrors.
App suites do not exercise these documentation-only moves.

## Recovery

Use the relocation map for incomplete documentation moves. Keep work on the feature branch.
Installer failures must retain the prior installation; preserve transaction recovery material if rollback fails.
Resume from the recorded pending step and repeat only invalidated checks.

## Progress

- [x] Implement the steps.
- [x] Verify acceptance and record evidence.
- [x] Publish the verified deliverable.

## Execution record

2026-11-14: moved 128 sections or invariant bullets with their requirement text preserved; rebased local links.
The extraction verified each original block against its destination. The relocation map records source hashes.
A separate link and byte audit covered 103 guidance documents and 57 instruction files with no errors.
Root: 6,783 bytes. Largest chain: 27,801 bytes. Largest repo-owned skill: 10,188 bytes.
`mise exec -- ruby Tools/Tests/sync_agents_test.rb`: 2 tests, 13 assertions, all passed.
`mise exec -- ./sync-agents` and `git diff --check`: passed.
The complete documentation diff was reviewed for preserved rules, explicit read conditions, and link destinations.
No app tests or formatting checks were run because this deliverable changes only Markdown.
The durable validator and hidden-directory mirror discovery follow in deliverable 03.

2026-11-14 publication: the user explicitly approved public publication. The reviewed branch is published in [PR #499](https://github.com/kyleve/Stuff/pull/499), ready for review.

## Resume point

Implementation is delivered. Continue any PR feedback through github-workflow. Linear linking remains unavailable without credentials.

The main integration preserves the new Device Layout Lab rule from `2e27fc5ba` verbatim in `Where/WhereUI/Sources/Developer/AGENTS.md`.
