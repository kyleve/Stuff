# Complete and focused agent guidance

## Planning checkpoint

- Updated: 2026-11-14; baseline `b629d56ac`.
- Operation: execute the user-approved native Claude discovery follow-up.
- Scope: all repository instruction chains; offline validation only.
- Stage: deliverables 01–05 are complete. [06 — Native Claude discovery](06-native-claude.md) is executing.
- Completed: original implementation, relocation verification, installer repair, offline validation, CI enforcement, focused checks, independent static review, reusable maintenance skill, and monthly schedule.
- Pending: publication of deliverable 06. Implementation, focused checks, and independent re-review pass. Linear linking remains unavailable.
- Next action: publish the compatibility migration and Linux bootstrap rename as separate commits, then update PR #499.
- Publication: user explicitly approved public publication on 2026-11-14. [PR #499](https://github.com/kyleve/Stuff/pull/499) is open and ready for review.
- Linear: duplicate lookup failed because the local CLI has no usable credentials. Issue search and linking remain unsent.

## Outcome and requirements

| Story | Requirement | Deliverable |
| --- | --- | --- |
| US-01: Agents receive all applicable instructions. | R-01: Root <= 8 KiB; every project chain <= 28 KiB; preserve requirements and exceptions. | [01](01-guidance.md) |
| US-02: Agents load relevant skill detail. | R-02: Repo-owned skill entry points <= 12 KiB; explicit routes; stable names and invocation policies. | [01](01-guidance.md) |
| US-03: Maintainers get one valid installed skill. | R-03: Repair duplicate packaging at the same revision; validate before transactional replacement. | [02](02-installation.md) |
| US-04: Invalid guidance fails repository checks. | R-04: Read-only offline validation of budgets, discovery inputs, and links; CI covers documentation-only changes. Q-08 replaces mirror checks with compatibility checks. | [03](03-validation.md), [06](06-native-claude.md) |
| US-05: Guidance stays focused as the repository grows. | R-05: Reusable normalization skill and a monthly scheduled audit using the existing guards. | [04](04-monthly-maintenance.md) |
| US-06: Claude uses the same guidance source. | R-06: Native AGENTS.md loading and linked skills replace copies, with migration that preserves unrecognized local content. | [06](06-native-claude.md) |

## Exclusions

- X-01: No app APIs, behavior, rendering, or Swift code changes.
- X-02: No live model evaluations, model credentials, or claims of improved skill activation.
- X-03: No higher Codex loading limit, external revision upgrades, or weakened engineering/publication policies.
- X-04: No generated Claude files in Git and no second backlog.

## Discovery and evidence

The baseline has 40 tracked instruction files. Root instructions occupy 52,692 bytes.
The largest observed chain is 99,292 bytes with separators, through WhereUI.
GitHub workflow and building-ui entry points exceed the selected skill budget.
The pinned Swift Testing package includes a nested Claude plugin variant in addition to its standalone entry point.
The current install command skips every existing root `SKILL.md`, even with that duplicate layout.
The current CI documentation shortcut skips the required lint job.

[OpenAI instruction discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md) documents a default 32 KiB project limit.
[Skill guidance](https://learn.chatgpt.com/docs/build-skills) supports focused entry points and conditional references.
[Evaluation guidance](https://developers.openai.com/blog/eval-skills) distinguishes structural checks from behavioral evidence.

## Shared decisions and questions

| ID | Status | Decision and source | Integration |
| --- | --- | --- | --- |
| Q-01 | closed | User selected all instruction chains on 2026-11-14. | R-01 and deliverables 01/03 |
| Q-02 | closed | User selected offline checks only on 2026-11-14. | R-04 and X-02 |
| Q-03 | closed | User approved the proposed plan and requested implementation. | Deliverables 01–03 and this checkpoint |
| Q-04 | closed | User explicitly approved public publication on 2026-11-14. | PR #499 |
| Q-05 | closed | User requested reusable monthly normalization and selected fresh Stuff tasks. | Deliverable 04 |
| Q-06 | closed | User explicitly approved monthly fresh tasks at the proposed cadence and PRs for fixes, without merging. | Active automation normalize-agent-guidance; deliverable 04 |
| Q-07 | closed | User approved the independent review's focused cleanup on 2026-11-14. Preserve requirements, checks, and audit evidence. | Deliverable 05; CI-test rewrite excluded |
| Q-08 | closed | User requested guidance and script changes to stop separate Claude copies. Anthropic documents native AGENTS.md and symlinked skill folders. | R-04/R-06 and deliverable 06; earlier mirror behavior is superseded |
| Q-09 | closed | The [user's PR comment](https://github.com/kyleve/Stuff/pull/499#discussion_r4576693763) requests renaming the Linux bootstrap because Cursor is no longer used. | Deliverable 06 moves the script and its Codex caller, then removes the unused launcher |

Preserve complete existing sections or invariant bullets when moving them. Record their new owners in the [relocation map](relocations.md).
Use source-scoped instruction files for subsystem invariants and conditional references for procedures or measurement history.
Use the existing FileTransaction for staged external-skill replacement.
Keep clean documentation PRs on the Linux fast path; repeat the validator in required lint so classification failure cannot conceal it.

## Shared contracts and recovery

Read the root repository contract, the Tools contract for command changes, and the guidance-authoring contract.
Use planning, skill-creator, simple-english, running-tests, code-review, and github-workflow as applicable.
Deliverables 01–05 used generated mirrors. Deliverable 06 replaces them with native instructions and skill links.
The validator reads canonical inputs and local compatibility state, then returns diagnostics and an exit status.
External installation flows from the pinned package through exclusions and validation to staged FileTransaction replacement, then skill-link setup.
No Swift API, actor, or app ownership changes are part of these deliverables.

Use the relocation map for incomplete documentation moves. Keep work on the feature branch.
Installer failures must retain the prior installation. If rollback fails, preserve transaction recovery material.
Resume from the recorded pending step and repeat only invalidated checks.

## Execution order and planning horizon

1. [01 — Guidance](01-guidance.md): restructure instructions and skills, update links, synchronize mirrors.
2. [02 — Installation](02-installation.md): exclusions, layout repair, transactional installation, focused tests.
3. [03 — Validation](03-validation.md): read-only checker, deterministic tests, and CI integration.
4. [04 — Monthly maintenance](04-monthly-maintenance.md): follow-up requested after publication; reusable skill and schedule.
5. [05 — Deduplication](05-deduplication.md): remove confirmed repetition and repair PR-template routes.
6. [06 — Native Claude discovery](06-native-claude.md): retire generated instruction copies and replace skill copies with links.

The original three deliverables were specified together because their interfaces and dependencies were established. Deliverable 04 records the later user request.
Each deliverable lands as a verified commit on the same feature branch.

## Plan review

Reviewed 2026-11-14 against `b629d56ac` and the user-approved chat plan.
Requirements, exclusions, dependencies, and acceptance conditions agree.
No unresolved technical decision blocks execution. Linear linking remains unavailable.
This is documentation and synchronous tooling work; no Swift architecture sketch is applicable.
The numbered plans describe the file and command flows directly; an additional diagram would duplicate those short flows.
Deliverable 05 was reviewed against `a650676ba`: its bounded cleanup preserves R-01 through R-05 and all exclusions.
The independent size review and subsequent source check identified its edits. No unresolved decision blocks execution.
Deliverable 06 was reviewed against `aaae5b0f8` and current Anthropic documentation. Its migration, contracts, and acceptance conditions agree.

## Review and delivery

Implementation PR: [#499](https://github.com/kyleve/Stuff/pull/499), ready for review.
Review focus: preserved requirements, installer rollback, byte accounting, Markdown parsing, and documentation-only CI failure propagation.
A fresh static subagent review is complete. Findings, corrections, coverage, and remaining validation limits are recorded in [03](03-validation.md).
The follow-up review and its corrections are recorded in [05](05-deduplication.md). No actionable findings remain in the reviewed scope.
The native Claude migration and bootstrap review are recorded in [06](06-native-claude.md), including four corrected failure cases and regression evidence.
These reviews were not live skill evaluations.

## Outcome

R-01 through R-04 are implemented, verified, and published in [PR #499](https://github.com/kyleve/Stuff/pull/499).
The newer main-branch Device Layout Lab invariant is preserved in its scoped owner. Native files remain identical to main.
Deliverables 01–05 are complete. Deliverable 06 records the subsequent user request.
The normalization skill is implemented and verified; its monthly schedule is active with explicit user approval.
The earlier automatic-review publication blocker was resolved by explicit user approval. Publication used the existing SSH credential because the OAuth credential lacked workflow scope.
The full requirements, decisions, execution order, and review record were restored in deliverable 04 after an earlier publication update truncated this overview.
