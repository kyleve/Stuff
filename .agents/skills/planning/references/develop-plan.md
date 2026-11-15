# Develop an initial plan

Follow the [Plans contract](../../../../Plans/AGENTS.md) for record structure and lifecycle.
For revisions, repeat only stages affected by new requirements, evidence, or decisions.

## Start the durable record

1. Read the request, supplied references, and related plans. Reuse existing session answers and authorization.
   Find or create the corresponding Linear issue through [todo-triage](../../todo-triage/SKILL.md), then link issue and plan both ways.
   If access is unavailable, retain pending issue work in the checkpoint and continue independent planning. Do not claim unsent updates succeeded.
2. Create the series directory using the user's local date; inspect an existing path before choosing another name.
   Start its README from [the overview template](../assets/overview.md), recording the outcome, constraints, assumptions, and questions before substantial research.
3. [Maintain the checkpoint](../SKILL.md#maintain-the-checkpoint) throughout discovery and review, including before numbered plans exist.

## Discover the requirements

Inspect current source, tests, module documentation, and applicable instructions. Identify reusable components and existing guards.
Treat documentation as a claim to verify against current behavior.
Record who has the problem, what success changes, required behavior, exclusions, and material constraints or failure cases.
For open-ended product work, walk through the main workflow, interruptions, and return visits before prescribing architecture.
Establish what the user sees, does, and expects to persist; use those scenarios to clarify ambiguous concepts.
Compare these with current behavior and repository contracts; record conflicts, ambiguous terms, and missing success criteria.
Use [the question loop](#resolve-questions) for decisions affecting behavior, scope, acceptance, architecture, compatibility, or delivery priorities.
Technical evidence establishes constraints, not product preferences. Ask about material product choices unless existing answers or explicit delegation cover them; resolve routine implementation details within those choices.
Record delegation scope and the decisions made within it. Distinguish proposals, user answers, and delegated selections.

## Research the unknowns

Tie technical questions to the requirements or decisions they affect.
Investigate repository code first; verify external claims against current primary documentation and the pinned tools or deployment targets.
Record sources, covered revisions/versions, implications, and unresolved claims in Research and evidence.
Compare meaningful alternatives against requirements, integration cost, and maintenance burden. Route unresolved product trade-offs through the question loop before selecting an approach.
Record the decision source and why alternatives were rejected, without inventing alternatives for routine choices.
If feasibility needs a prototype, plan an [experiment deliverable](../../../../Plans/AGENTS.md#experiment-deliverables); execute it only within existing authorization.
For an interactive browser experiment, use [Browser prototypes with Astro](browser-prototypes.md) to specify the development loop and device-preview evidence.
Stop when material decisions have enough evidence and remaining uncertainty is explicit. Record when repository evidence suffices without external research.

## Resolve questions

Use the [question register and statuses](../../../../Plans/AGENTS.md#questions) after discovery and whenever later work exposes a decision.

1. Reuse the existing question ID for the same decision. Resolve factual questions from available evidence before asking the user.
   Ask a small batch of remaining questions, with concrete options and trade-offs, prioritizing blockers. Reuse applicable answers.
2. Record each answer's source and date; link GitHub comments. Mark complete answers `answered`, leaving partial or conflicting answers `open` with the remaining uncertainty.
3. Integrate through [Apply a revision](revise-plan.md). Link its affected sections and review result before closing the question.
   For a question that no longer applies, record the scope decision that removed it.
   During product discovery, reflect the emerging workflow and consequential assumptions to the user after each answer batch. Ask another focused batch only if material choices remain; no minimum number of questions or rounds is required.
4. Apply the contract's deferral rules. File work outside the series through todo-triage; keep current-horizon plans blocked where the answer is still required.
   A later question also blocks earlier work that embeds its answer in a model, API, or acceptance criterion. Independently testable groundwork does not bypass that product dependency.
5. [Review the plan](#review-the-plan) after integration. Reopen invalidated answers or due deferrals, retaining their history; repeat only affected research and review.
6. While input is pending, continue independent work. Do not spin, repeat answered questions, or treat elapsed time as an answer.
   Return unresolved questions with their next actions.

## Draft the executable plans

Select the planning horizon's size and order from the evidence and requested scope.
When plausible first deliverables validate different product assumptions, resolve delivery priority through existing answers, explicit delegation, or a focused question before detailing it.
Use [the plan template](../assets/plan.md) for that horizon and [the outline template](../assets/outline.md) for later selected work.
Split at independently verifiable deliverables, keeping setup and documentation with the deliverable that needs them.
Apply the contract's requirement mapping, dependencies, and [design requirements](../../../../Plans/AGENTS.md#reviewable-design).
Prefer sequential execution unless independent work benefits materially from parallel execution, within session delegation rules.
Write concrete steps for the current horizon: affected paths, interfaces, observable outcomes, repository-relative commands/working directories, and recovery from partial operations.
Link shared context instead of copying definitions. Replace template instructions with concrete content or explicit questions.

## Review the plan

Review the whole series for scope and dependency consistency, and the current horizon for executable detail.
Check later outlines against the [rolling-wave contract](../../../../Plans/AGENTS.md#rolling-wave-planning), rather than demanding premature implementation detail.

- Trace stories through requirements, deliverables, and acceptance. Find unowned requirements, unnecessary steps, scope additions, and contradictions with exclusions or decisions.
- Compare design with source, module boundaries, supported versions, and evidence. Check ownership and interfaces across diagrams, sketches, and steps, including failure, cancellation, persistence, and recovery paths.
- Verify that the proposed checks distinguish success from failure and cover material constraints. Experiment acceptance measures evidence, not whether the hypothesis succeeds.
- Verify Mermaid syntax and rendering when a renderer is available; otherwise record the limit. Swift pseudocode is not compilation evidence.
- Read as an executor without prior chat context. Find missing prerequisites or decisions; distinguish deliberate later uncertainty from questions that block earlier work.

Correct supported findings and repeat affected comparisons. Return new questions to the caller instead of starting a nested question loop.
Record the date, source revision, reviewed scope, findings, dispositions, and limits in Plan review. Do not imply implementation verification.
Before marking a plan ready, verify that its material product decisions are supported by user answers or explicit delegation and that no unresolved question prevents implementation or acceptance.
Check decisions against the scope of those answers or delegation; technical review alone does not establish intended product behavior.
Apply the contract's readiness rules. Preserve valid `executing`, `complete`, or `superseded` records and later `outline` status.
Return to the caller without publishing; initial development returns to [Create a plan](../SKILL.md#create-a-plan) for handoff.

## Advance the planning horizon

After a deliverable completes, a refinement trigger occurs, or the user requests refinement:

1. Read actual outcomes, verification evidence, source changes, and feedback. Integrate experiment conclusions with their limits; reopen invalidated questions.
2. Reconsider order, dependencies, and assumptions within the authorized scope. Use [Apply a revision](revise-plan.md) for splits or supersession.
3. Record the next horizon, evidence, and selection reason. If a required trigger is pending, record its next action and continue only independent work.
4. Mark selected outlines `draft` and expand the same files with executable sections. Preserve decisions, question links, and existing content; do not overwrite with a blank template.
   Repeat affected discovery, research, question integration, and review. Record blockers when required evidence is unavailable.
5. Return reviewed plans and pending questions to the caller for checkpoint and publication. Implementation still requires existing authorization and readiness.
