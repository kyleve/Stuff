---
name: normalize-agent-guidance
description: Audit and normalize repository instructions and owned skills for size, duplication, and discovery drift. Use for the monthly guidance maintenance run or a requested instruction cleanup.
---

# Normalize agent guidance

Read the [repository contract](../../../AGENTS.md), [guidance ownership](../../../.agents/AGENTS.md), and [maintenance procedure](../../../.agents/references/agent-maintenance.md).
Use this skill to keep guidance complete, focused, and within the existing budgets.
For an audit-only request, report proposed corrections without changing files or publishing.
[review-lessons](../review-lessons/SKILL.md) owns historical review audits; this skill owns the current instruction structure.

## Establish the scope and baseline

- Respect an explicitly selected checkout or base. For unattended runs, use an isolated worktree from current `origin/main`.
- Search open PRs for an unfinished guidance-normalization run before creating another branch. Continue a matching PR through [github-workflow](../github-workflow/SKILL.md).
- If the selected revision lacks this skill or `./sync-agents --check`, report the missing rollout prerequisite and stop. Do not reconstruct unmerged tooling.
- Record the source revision and the prior completed audit's revision from its PR or run summary. If none is available, establish a baseline without claiming a growth comparison.
- Cover all repository instruction chains, owned skill entry points, and their required references. Read each affected module's instructions before relocating its rules.

## Measure and inspect

Run `mise exec ruby -- ./sync-agents --check` before editing. Retain its diagnostics and reported coverage gaps.
Use the [validator](../../../Tools/agent_guidance.rb) for budgets, override precedence, and combined-chain accounting.
Use [AgentFiles](../../../Tools/agent_files.rb) for the canonical inventory and raw UTF-8 file sizes to rank individual instructions and owned skill entry points.
Compare changed guidance with the prior audit when its revision is available.

Review the largest and fastest-growing files, plus guidance changed since the prior audit.
Prioritize small remaining headroom, repeated rules, source inventories copied into prose, and procedures in always-loaded instructions.
Also inspect broken required-read routes, conflicting instructions, stale references, and ambiguous skill descriptions.
A passing size check does not establish that guidance remains well placed or discoverable.

Do not count generated mirrors or absent external installations as audited source content.
The [checker scope](../../../Tools/README.md#agent-guidance-tools) defines its coverage and parser limits.
If changing assumptions about Codex loading or skill behavior, verify them through the available openai-docs workflow first.

## Make supported corrections

- Strengthen the existing owner of each rule. Remove duplication only after preserving the requirement, its conditions, exceptions, and guard links there.
- Move subsystem invariants into the deepest applicable instruction file. Put conditional procedures in the owning skill or a required reference.
- Add an explicit read condition for every extracted reference. Preserve routes for callers and tests outside the new source directory.
- Keep general engineering rules, branch/publication policies, and skill invocation behavior intact. Do not raise budgets or change Codex configuration to make a failing check pass.
- Keep external pins and fetched source contents unchanged. Report installed-package failures or use the existing maintenance procedure when repair is within the request.
- Keep application behavior and unrelated tooling changes outside this normalization pass. Report a blocker when a correction needs a policy decision or separate implementation.
- For relocations, record an old-owner to new-owner map in the PR or an existing execution record. Compare the original rule text with the result, including its exceptions.

Do not rewrite clear guidance merely to reduce its byte count or meet a monthly quota.
When no supported correction remains, leave tracked files unchanged and report the audit result.

## Verify and deliver

After changes, run `mise exec ruby -- ./sync-agents`, then `mise exec ruby -- ./sync-agents --check`.
Validate changed skills through skill-creator when available. Review the complete diff through [code-review](../code-review/SKILL.md).
Use the existing tests for any changed executable guard; documentation moves alone do not need app builds or model evaluations.
If changes are warranted, publish a ready-for-review PR through github-workflow and leave it open for review.
Do not create a commit or PR solely to record a clean run.

Report the source and comparison revisions, instruction/skill counts, root size, largest chain, largest owned entry points, and remaining headroom.
Include growth where a baseline exists, corrections and relocation map, checks run, PR link, and any incomplete coverage or blocked publication.
Keep this record in the PR or run summary so the next audit can compare results.
Offline checks establish structure and discovery inputs, not model activation or task quality.

For a requested schedule, invoke `$normalize-agent-guidance` from the automation prompt. Keep the procedure here and the cadence in the scheduler.
