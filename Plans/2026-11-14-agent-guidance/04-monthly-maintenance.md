# Reusable monthly guidance maintenance

Status: complete
Dependencies: [03](03-validation.md)

## Requested outcome

US-05 / R-05: Keep instruction size and discovery from drifting through a reusable repository skill and a monthly scheduled run.
The user requested this follow-up after publication of [PR #499](https://github.com/kyleve/Stuff/pull/499).
Preserve R-01 through R-04 and the exclusions in the [overview](README.md).
Use offline checks. The scheduled workflow may publish supported documentation corrections for review; it does not merge them.

## Implementation

1. Add `normalize-agent-guidance` with focused discovery metadata and no duplicate budget implementation.
2. Reuse the existing validator and ownership rules. Cover growth, duplication, preservation, required-read routes, and clean runs that need no changes.
3. Link the skill from agent maintenance. Validate its frontmatter, local links, mirrored links, and budgets.
4. Review the skill statically and publish it in the existing PR.
5. Create one monthly automation after checking for an existing matching task. Record its destination and cadence.

## Verification and limits

Run skill-creator's quick validator when its dependencies are available, synchronize mirrors, and run `./sync-agents --check`.
Inspect a read-only baseline report against the current branch and review the scheduled prompt against the skill.
No new script, native suite, or live model evaluation is needed for this documentation workflow.
Use a stable project destination for fresh tasks if selected; do not bind a recurring project job to a disposable checkout.

## Decisions

- Proposed cadence: first Monday each month at 09:00 America/New_York.
- Destination: fresh Stuff project tasks, explicitly selected by the user.
- Reuse the existing Stuff maintenance model and reasoning settings for a standalone project task.

## Active schedule

Run the monthly audit on the first Monday at 09:00 America/New_York.
The prompt invokes `$normalize-agent-guidance`, works from current main or a matching audit PR, and reports measurements and blockers.
Supported corrections may become ready-for-review PRs; the automation never merges them.
The user explicitly selected fresh Stuff tasks and authorized opening PRs for supported fixes.
Automation `normalize-agent-guidance` is active in the Stuff project. It reuses the existing maintenance settings: gpt-6-astra with high reasoning effort.

Saved task prompt:

> Run $normalize-agent-guidance for the Stuff repository at /Users/kve/Development/Stuff, following .agents/skills/normalize-agent-guidance/SKILL.md and the applicable repository instructions. Use an isolated worktree from current origin/main, or continue an existing matching normalization PR as the skill directs. Audit all instruction chains and owned skills for budget headroom, growth, duplication, and broken required-read routes. Reuse the existing offline validator and preserve requirements, exceptions, and guard links. Publish supported guidance corrections in a ready-for-review PR and leave it open; do not merge. If no correction is justified, leave tracked files unchanged and report the baseline and headroom. Record revisions, coverage, before/after measurements, checks, PR links, and blockers in the run summary. If the skill or checker has not reached the selected revision, report the missing prerequisite and stop. Keep validation offline; do not run live model evaluations.

## Progress

- [x] Read current tooling, skill conventions, existing maintenance automation, and official scheduling guidance.
- [x] Implement and verify the skill.
- [x] Publish the reviewed changes.
- [x] Create and verify the monthly schedule.

## Execution record

The repository checker passes for 57 instruction files and 13 owned skills.
Root: 6,783/8,192 bytes. Largest chain: 27,801/28,672 bytes. Largest owned skill: code-review at 10,188/12,288 bytes.
The read-only baseline reused AgentGuidance for chain accounting and AgentFiles for canonical inventory.
The original overview's requirements, decisions, execution order, and review record were restored from `2aeb63e0b` after an earlier publication update truncated them.

The bundled Python skill validator could not start because PyYAML is missing.
Automatic approval review rejected downloading that dependency under the offline-only constraint.
The existing Ruby repository validator checks metadata, discovery, links, mirrors, and budgets; static inspection also checks scaffold removal and invocation metadata.
No live model evaluation was performed.

An attempted first-Monday 09:00 task in the current chat was rejected by automatic approval review.
It requires explicit approval of cadence, destination, and recurring PR publication. No automation was created.

Fresh static review found no actionable issues in the skill, its metadata, required-read routes, or restored plan overview.
The new entry point occupies 5,393 bytes. The repository validator, attribution check, YAML metadata inspection, and whitespace check pass.
The skill is delivered through [PR #499](https://github.com/kyleve/Stuff/pull/499); the schedule is now active after the user's explicit approval.

2026-11-14: the user selected fresh Stuff tasks and then explicitly authorized PRs for fixes. The scheduler created the active monthly automation.
Readback verified the project target, first-Monday 09:00 cadence, skill invocation, isolated worktree instruction, and prohibition on merging.

## Resume point

The skill and schedule are delivered. The first run must use the merged skill and checker; if either prerequisite is absent, it reports the blocker.
Local runs require the app and computer to remain running. Keep prior deliverables complete.
