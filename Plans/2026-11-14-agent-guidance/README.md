# Complete and focused agent guidance

## Planning checkpoint

- Updated: 2026-11-14; baseline `b629d56ac`.
- Operation: execute the user-approved plan.
- Scope: all repository instruction chains; offline validation only.
- Stage: local implementation and review complete; publication blocked.
- Completed: all three deliverables, relocation verification, installer repair, offline validation, CI enforcement, focused checks, and independent static review.
- Pending: publication and Linear linking.
- Next action: obtain explicit permission to publish the verified branch, then push and open a ready-for-review PR.
- Publication: automatic approval review rejected a push to public `kyleve/Stuff`; explicit publication permission will be requested after the complete diff is verified.
- Linear: duplicate lookup failed because the local CLI has no usable credentials. Issue search and linking remain unsent.

## Outcome and requirements

| Story | Requirement | Deliverable |
| --- | --- | --- |
| US-01: Agents receive all applicable instructions. | R-01: Root <= 8 KiB; every project chain <= 28 KiB; preserve requirements and exceptions. | [01](01-guidance.md) |
| US-02: Agents load relevant skill detail. | R-02: Repo-owned skill entry points <= 12 KiB; explicit routes; stable names and invocation policies. | [01](01-guidance.md) |
| US-03: Maintainers get one valid installed skill. | R-03: Repair duplicate packaging at the same revision; validate before transactional replacement. | [02](02-installation.md) |
| US-04: Invalid guidance fails repository checks. | R-04: Read-only offline validation of budgets, discovery inputs, links, and present mirrors; CI covers documentation-only changes. | [03](03-validation.md) |

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
| Q-03 | closed | User approved the proposed plan and requested implementation. | All three deliverables and this checkpoint |

Preserve complete existing sections or invariant bullets when moving them. Record their new owners in the [relocation map](relocations.md).
Use source-scoped instruction files for subsystem invariants and conditional references for procedures or measurement history.
Use the existing FileTransaction for staged external-skill replacement.
Keep clean documentation PRs on the Linux fast path; repeat the validator in required lint so classification failure cannot conceal it.

## Execution order and planning horizon

1. [01 — Guidance](01-guidance.md): restructure instructions and skills, update links, synchronize mirrors.
2. [02 — Installation](02-installation.md): exclusions, layout repair, transactional installation, focused tests.
3. [03 — Validation](03-validation.md): read-only checker, deterministic tests, and CI integration.

All three deliverables are specified now because their interfaces and dependencies are established.
Each deliverable lands as a verified commit on the same feature branch.

## Plan review

Reviewed 2026-11-14 against `b629d56ac` and the user-approved chat plan.
Requirements, exclusions, dependencies, and acceptance conditions agree.
No unresolved technical decision blocks execution. Linear linking remains unavailable.
This is documentation and synchronous tooling work; no Swift architecture sketch is applicable.
The numbered plans describe the file and command flows directly; an additional diagram would duplicate those short flows.

## Review and delivery

Implementation PR: pending publication.
Review focus: preserved requirements, installer rollback, byte accounting, Markdown parsing, and documentation-only CI failure propagation.
A fresh static subagent review is complete. Findings, corrections, coverage, and remaining validation limits are recorded in [03](03-validation.md).
No actionable findings remain in the reviewed scope. This review was not a live skill evaluation.

## Outcome

The local branch implements and verifies R-01 through R-04. All three plans await publication before lifecycle completion.
Automatic approval review rejected public publication of repository guidance, even after the configured destination and repository ownership were verified.
The complete branch is ready for explicit publication approval. No push or PR is claimed.
