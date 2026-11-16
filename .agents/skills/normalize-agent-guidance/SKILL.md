---
name: normalize-agent-guidance
description: Audit and simplify repository instructions and owned skills, including size, duplication, task routing, and discovery.
---

# Normalize agent guidance

Use the [guidance ownership rules](../../../.agents/AGENTS.md).
For audit-only requests, report proposals without editing or publishing.
[review-lessons](../review-lessons/SKILL.md) owns historical review audits.

## Establish the baseline

- Use the selected checkout; unattended runs start from current `origin/main` in an isolated worktree. Continue an unfinished matching PR when one exists.
- Record the source revision and the prior completed audit revision, or establish a first baseline.
- Run `mise exec ruby -- ./sync-agents --check`. Use [AgentFiles](../../../Tools/agent_files.rb) for canonical inventory and [the validator](../../../Tools/agent_guidance.rb) for budgets and chain accounting.
- Cover instruction chains, owned skill entry points, and required references. Count canonical sources once; report absent external installations and other coverage gaps.

## Remove content that does not change a decision

Prefer deletion for generic engineering advice, behavior inferable from code, copied inventories, algorithm walkthroughs, and repeated rationale.
Keep repository preferences, non-obvious constraints, exceptions, and useful guard links. Do not remove a safety or compatibility requirement merely because code currently enforces it.

For common tasks, trace the instructions and skills they encounter. Narrow unnecessary triggers and required reads; shorten descriptions to the actual capability.
Use conditional references for substantial specialized procedures, not to preserve unnecessary prose.
Keep caller/test routes when moving source-directory contracts.

Read each changed owner's instructions. Record significant deletions and relocations with their rationale in the PR.
Changes to explicit workflow preferences, authorization boundaries, or skill availability need existing user authorization; otherwise report a proposal.
Keep external pins and fetched contents unchanged unless the task includes their maintenance.
Verify changed loading assumptions through official OpenAI guidance.
[Maintenance](../../../.agents/references/agent-maintenance.md) covers installation and Claude compatibility.

## Verify and deliver

- Run `mise exec ruby -- ./sync-agents`, then `mise exec ruby -- ./sync-agents --check`.
- Validate changed skills through skill-creator. Review representative positive and negative task routes when triggers change; distinguish static inspection from observed activation.
- Keep existing budgets. Use existing tests for changed executable guards; text-only edits need no app builds.
- Review through [code-review](../code-review/SKILL.md) and publish supported changes through [github-workflow](../github-workflow/SKILL.md). Leave the PR open.

Report revisions, counts, root/chain/entry-point sizes and headroom, growth or reduction, significant deletions/relocations, checks, and coverage limits.
A passing structural check does not establish model behavior. A clean audit needs no commit or PR.
Keep the run record in the PR or response. Schedules invoke `$normalize-agent-guidance`; cadence belongs in the scheduler.
