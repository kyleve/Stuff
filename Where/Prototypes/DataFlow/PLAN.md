# Where live data flow prototype

Status: initial research and discussion. Implementation has not started.
Updated: 2026-10-23.

## Goal

Build a prototype that shows real data flowing through the running Where app.
Develop the design through discussion and small, reviewable PRs.
Keep this file as the current plan and [Research/](Research/README.md) as the supporting record.

The user requested this document workflow on 2026-10-23.
The user selected both a separate Mac window and a view inside Where.
Instrumentation, transport, presentation reuse, and first-flow selection remain open.
The proposals in this plan do not record user approval of those choices.

## Current position

The repository already provides typed events, spans, live log streams, and an on-device trace viewer.
Its store change stream carries no causal identity.
Its span tree uses time containment, which does not establish data lineage.
The [repository research](Research/002-repository-map.md) records the evidence and its limits.

The immediate discussion is what one useful trace must explain and how both viewing surfaces share its meaning.
The [decision register](Research/003-decisions.md) holds the options and unresolved questions.

## Proposed first result

A developer performs an ordinary action in Where and sees the resulting work update live.
Both a separate Mac window and an in-app view must support this goal.
Selecting one operation reveals its observed stages, outcomes, and links to the affected data.
The viewer distinguishes recorded relationships from incomplete or inferred relationships.

The initial candidate is a manual day edit through its store commit, derived outputs, and report refresh.
This action is repeatable and does not depend on passive GPS delivery.
GPS ingestion is a second candidate, especially for retries and the location outbox.
Both candidates use the normal app services.

Proposed acceptance criteria:

- One real action produces an inspectable flow while Where remains usable.
- Both surfaces describe the same observed work consistently. Their layouts can differ.
- The viewer identifies the observed input, commit, downstream work, and terminal outcomes.
- Concurrent operations remain distinguishable. Time overlap alone creates no causal edge.
- Failed, skipped, cancelled, and incomplete work remain visible as distinct outcomes.
- Pausing the display does not pause domain work. Capture behavior during pause is explicit.
- The viewer shows capture gaps, connection loss, and unavailable history honestly.
- Capture and presentation have measured, bounded resource costs.

Exact latency, event-volume, and memory budgets remain undecided.
Fixtures support development and tests. A fixture-only demonstration does not complete the live-flow result.

## Proposed sequence of PRs

These are candidate boundaries. Each implementation slice needs a concrete scope before work starts.
Create the actual stack after the first implementation decisions establish its dependencies.

| Slice | Result | Evidence required to finish |
| --- | --- | --- |
| D0 — Planning documents | This plan, research index, initial source map, and decision register | Links resolve, findings cite source, and proposals remain explicit |
| P1 — Observation contract | Defined stages, operation/data identities, causal links, outcomes, capture lifecycle, and owning modules | One chosen flow can be described without inventing causality |
| P2 — First live flow | Minimum instrumentation, capture adapter, and viewer for the chosen flow | An ordinary action in the running app appears live through its selected boundaries |
| P3 — Both surfaces and inspection | The companion surface, selection, filtering, display pause, and bounded recent history | Both viewers explain the same live operation and its recent outcome |
| P4 — Failure and concurrency | Retry, overlap, cancellation, reset, and capture-gap behavior | Controlled scenarios preserve domain results and expose incomplete observation |
| P5 — Broader coverage | Additional flows selected from prototype findings | Each added flow answers an agreed debugging question |

P2 can split into dependent capture, transport, and presentation PRs after the first flow is chosen.
Its completion criterion remains an end-to-end live demonstration.
The order of the two surfaces remains open. The full prototype requires both.
Durable replay, remote-device support, and wider reuse need separate decisions before entering the stack.

## Design boundaries to preserve

These existing contracts constrain the prototype. They do not select its architecture.

| Contract | Owner and existing evidence |
| --- | --- |
| One active app world supplies shared resources through its composition root | [Where scope rules](../../AGENTS.md#scopes-and-the-launch), including reset and demo guard tests |
| Store mutations use `perform`. Values cross the persistence boundary | [WhereCore rules](../../WhereCore/AGENTS.md#shape--invariants) and `SwiftDataStoreTests` |
| Production refresh remains driven by the existing change signal | [Where layering](../../AGENTS.md#layering) and [WhereStore](../../WhereCore/Sources/Persistence/WhereStore.swift) |
| Generic observability cannot depend on Where | [Periscope layering](../../../Shared/Periscope/AGENTS.md#modules--dependencies) |
| Logging fields retain their classification and export controls | [PeriscopeCore rules](../../../Shared/Periscope/PeriscopeCore/AGENTS.md#invariants) |
| Developer tooling must avoid logging refresh loops | [PeriscopeTools rules](../../../Shared/Periscope/PeriscopeTools/AGENTS.md#invariants) |

Observation must not open another domain store or become a required step for committing user data.
Any proposal to change a contract needs its own rationale, tests, and owning documentation.
The first slice must define how capture ends or rebinds across scope replacement.

## Validation approach

The initial research is source inspection only. No app run, capture, benchmark, or runtime test has occurred.
The documentation change needs link, diff, and wording checks.

Implementation validation will cover event meaning, causal links, capture lifetime, and bounded retention.
Controlled tests must cover overlapping work, rollback, retries, and slow consumers.
Tests use isolated stores and scripted inputs under the repository rules.
Live acceptance needs an identified build, observation environment, action, and resulting trace.
Measure capture costs with capture disabled and enabled on the same workload.

When selecting implementation checks, use the [running-tests skill](../../../.agents/skills/running-tests/SKILL.md).
UI work also uses the [building-ui skill](../../../.agents/skills/building-ui/SKILL.md).

## Keeping the record current

1. Read this plan and the research index before continuing work.
2. Record substantive research or discussion in a numbered document under `Research/`.
3. Label source observations, proposals, decisions, and open questions separately.
4. After a decision, update this plan and link its rationale from the decision register.
5. Add branch, PR, and validation links to the relevant slice as work becomes concrete.
6. Preserve superseded research with a dated correction and a link to its replacement.

The [Where backlog](../../TODOs.md) holds the exploratory work item.
This requested plan records design and sequencing. Research documents do not create separate task lists.
File unrelated findings in their owning `TODOs.md` and link them from research.

## Progress

- 2026-10-23: Created the planning workspace and initial source research.
- 2026-10-23: Recorded the user's choice to support both Mac and in-app viewing.
- No implementation slice is complete.
