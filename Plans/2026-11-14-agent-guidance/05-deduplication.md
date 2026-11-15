# Focused guidance deduplication

Status: complete
Dependencies: [04](04-monthly-maintenance.md)
Requirements: preserve R-01 through R-05 and X-01 through X-04 from the [overview](README.md).
Authorization and review: Q-07; baseline `a650676ba`.

## Scope and acceptance

Consolidate repeated testing, publication, ownership, UI, and fixture guidance at their existing owners.
Replace repetitive navigation with explicit task tables. Fix the two stale PR-template section references.
Keep unique exceptions, guard links, invocation policies, completed execution evidence, and the original relocation map.
Share the identical flow and recovery text for plans 01–03. Remove only the redundant helper-level fetch-failure test.
Retain the public-command failure test and the CI-expression tests. No production code or scheduler changes are needed.

The guidance contract owns preservation and read routes; `./sync-agents --check` guards structure, links, mirrors, and budgets.
The Tools contract requires public-command coverage; `SyncAgentsCommandTest` retains fetch diagnostics and file-preservation assertions.
Compare removed rules with their retained owners, inspect template references, and run the affected synchronization suites.
Synchronize mirrors, run the repository checker, review the complete follow-up, then commit and update PR #499.

## Retained owners

| Removed repetition | Retained owner |
| --- | --- |
| Testing reference | [running-tests](../../.agents/skills/running-tests/SKILL.md), including macro and host-test exceptions |
| Branch, commit, push, and ready-PR policy | [Root contract](../../AGENTS.md#working-in-this-repo) |
| Ownership and mirrors | [Guidance contract](../../.agents/AGENTS.md) |
| Broadway traits and repository hygiene | [Broadway reference](../../.agents/skills/building-ui/references/broadway.md) and root contract |
| PR shapes and operation routes | [PR writing](../../.agents/skills/github-workflow/references/pr-writing.md) and the owning skill tables |
| WhereCore test fixtures | [Where testing](../../Where/Guidance/testing.md), with Core-only requirements retained locally |
| Common plan flow and recovery | [Overview](README.md#shared-contracts-and-recovery) |
| Helper fetch-failure test | [Public-command regression](../../Tools/Tests/sync_agents_command_test.rb) |

## Progress and recovery

The baseline checker passes: 57 instruction files, 13 owned skills, and a largest chain of 27,801 bytes.
The checker passes after synchronization. Root: 6,673 bytes; largest chain: 27,691 bytes; largest owned entry: 10,188 bytes.
The affected synchronization suites pass: 10 tests, 82 assertions. Template routes, unchanged skill metadata, and whitespace checks pass.
Static review restored explicit trait-read declaration requirements and PR architecture/compatibility clauses at their retained owners. No actionable findings remain.
The Python skill validator still lacks PyYAML; repository validation covers metadata and links. Native tests and live model evaluations are outside scope.
Published as `76aa17e62` in [PR #499](https://github.com/kyleve/Stuff/pull/499), with the description and validation evidence updated.
Resume with PR feedback. For incomplete consolidation, restore the baseline block and repeat affected checks.
