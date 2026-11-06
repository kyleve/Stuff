# Develop an initial plan

Use this procedure to turn a request into a reviewable execution plan.
For revisions, repeat only stages affected by new requirements, evidence, or decisions.
Planning can produce incomplete drafts for discussion. Readiness requires the review described here.

## Start the durable record

1. Read the request, supplied references, and existing related plans or backlog items.
   Use existing session answers and authorization.
2. Create `Plans/YYYY-MM-DD-<topic>/` using the user's local date.
   If that path already exists, inspect it before selecting another unique name.
   Copy [the overview template](../assets/overview.md) to the series `README.md`.
   Replace placeholders as facts become known.
3. Record the initial outcome, known constraints, and open questions before substantial research.
   Separate user requirements, observed behavior, and assumptions.
   Update these files throughout discovery instead of keeping findings only in chat.
4. Initialize the overview's Planning checkpoint through [Maintain the checkpoint](../SKILL.md#maintain-the-checkpoint).
   Maintain it through discovery, research, questions, drafting, and review, even before numbered plans exist.

## Discover the requirements

1. Identify the affected users or maintainers and their current problem.
   Describe what success changes for them.
2. Inspect the current source, relevant tests, module documentation, and applicable `AGENTS.md` files.
   Identify reusable components, existing guards, and required skills.
   Treat unverified documentation as a claim to investigate, not proof of current behavior.
3. Gather user stories, required behavior, exclusions, and operational constraints.
   Cover relevant failure cases, data compatibility, permissions, accessibility, performance, and deployment constraints.
   Include only concerns that materially affect this work.
4. Compare the request with the current behavior and repository contracts.
   Record ambiguous terms, conflicting requirements, unsupported assumptions, and missing success criteria.
5. Ask focused questions that change scope, acceptance, architecture, or compatibility.
   Resolve questions from available sources before asking the user.
   Offer concrete options and trade-offs where useful.
   Continue independent discovery while awaiting answers.
   Do not repeat answered questions or treat silence as agreement.
6. Record answers and their sources in the overview's question register.
   Label reasonable implementation assumptions explicitly.
   Use [the question loop](#resolve-questions) to integrate answers and track unresolved decisions.

## Research the unknowns

1. List the technical questions that prevent a credible plan.
   Tie each question to a requirement or design decision.
2. Investigate repository code and tests first.
   Use current primary documentation for external APIs, platform behavior, or dependencies that the design relies on.
   Verify version-specific claims against the repository's pinned tools and deployment targets.
3. Record findings, source paths or URLs, and their implications in Research and evidence.
   Distinguish observed facts from inferences and unresolved claims.
   State which revision or version the evidence covers where relevant.
4. When meaningful alternatives exist, compare them against requirements, exclusions, integration cost, and maintenance burden.
   Record the selected approach and why alternatives were rejected in Shared decisions.
   Do not manufacture alternatives for routine choices.
5. If feasibility needs a prototype, describe a bounded experiment with a question and success criterion.
   Perform only experiments covered by the current authorization.
   Otherwise include the experiment as an explicit planned step and retain the feasibility gap.
   Do not start product implementation merely to finish a planning request.
6. Stop research when material decisions have sufficient evidence and remaining uncertainty is explicit.
   For familiar work without external unknowns, record the repository evidence and why external research was unnecessary.

## Resolve questions

Use this loop after discovery and research, and whenever drafting, review, or execution exposes a new question.
Use the statuses defined in the [Plans contract](../../../../Plans/AGENTS.md#questions).

1. Collect unresolved questions in the overview with stable `Q-NN` IDs.
   Record affected requirements or plans, blocking impact, and the next action.
   Reuse an existing question for the same decision rather than creating a duplicate.
2. Resolve factual questions from available evidence before asking the user.
   Ask a small, focused batch of remaining questions, starting with those that block important decisions.
   Include the question IDs, concrete options, and relevant trade-offs.
   Do not ask again when an existing answer still applies.
3. Record each answer, its source, and date, then mark the question `answered`.
   Link GitHub answers to their comments. Summarize chat answers with their date.
   If an answer is partial or conflicting, keep the question `open` and identify what remains unresolved.
4. Integrate the answer through [Apply a revision](revise-plan.md).
   Collect its review result and any new questions before continuing this loop.
5. Link the integrated sections and review result from the question's resolution record.
   Mark the question `closed` only when the revision procedure confirms integration and review are complete.
   If the question no longer applies, record the reason and relevant scope decision before closing it.
6. For intentional deferral, record the reason, revisit condition, next action, and a backlog link for remaining work.
   Mark the question `deferred` without treating it as answered.
   For a blocking question, keep affected plans blocked.
   Only an integrated answer or authorized removal of the dependency clears that blocker.
7. After closing questions, refresh readiness through [Review the plan](#review-the-plan).
   Collect any new questions before the next iteration of this loop.
   If evidence invalidates a closed answer or a deferral's revisit condition occurs, reopen that question with its history intact.
   Repeat the affected research, question, and review steps until no further answers are needed for the selected scope.
8. If user input is pending, continue independent work and preserve the exact pending questions for handoff.
   Do not spin on unanswered questions or infer answers from elapsed time.
   Return unresolved blockers and deliberately deferred questions with their next actions.

## Draft the executable plans

1. Give stories, requirements, and exclusions stable IDs in the overview.
   Define both unnecessary capabilities and explicitly avoided approaches.
2. Copy [the plan template](../assets/plan.md) to `01-deliverable.md`.
   Start with one plan. Split at independently verifiable deliverables or useful review boundaries.
   Keep setup and documentation with the deliverable that needs them.
3. List plans in execution order and give each plan explicit dependency links.
   Map every requirement to an implementing plan and acceptance criteria.
   Prefer sequential execution unless independent work materially benefits from parallel execution.
   Follow the session's delegation rules.
4. Write concrete steps with affected paths, interfaces, and observable results.
   Use repository-relative paths and working directories for commands.
   Include recovery instructions for operations that can leave partial state.
5. Describe data flows with fenced Mermaid diagrams using actual component names and data passed between them.
   Sketch proposed ownership, interfaces, and composition with fenced Swift pseudocode.
   Label existing APIs, proposed APIs, assumptions, and omitted details.
   If a diagram or sketch does not apply, record the reason.
6. Link shared context instead of copying definitions across plans.
   Replace remaining template instructions with concrete content or an explicit unresolved question.

## Review the plan

Review the complete series before marking plans ready, including changes from direct feedback or GitHub comments.

1. Trace each user story through requirements, implementing plans, and acceptance criteria.
   Find missing requirements, unowned requirements, and implementation steps without a requirement or necessary supporting role.
2. Compare requirements with exclusions and user decisions.
   Find contradictions, accidental scope additions, and assumptions presented as agreed requirements.
3. Compare the design with current source, module boundaries, supported versions, and repository rules.
   Find invented existing APIs, missing integration work, and claims unsupported by the recorded evidence.
4. Trace data and ownership across Mermaid diagrams, Swift sketches, and implementation steps.
   Find mismatched interfaces, missing producers or consumers, dependency cycles, and conflicting execution order.
   Inspect relevant failure, cancellation, persistence, and recovery paths.
5. Verify that acceptance criteria distinguish success from failure and cover material constraints.
   Verify that each deliverable can be demonstrated with the proposed commands or procedures.
   If a renderer is available, verify Mermaid syntax and rendering.
   Otherwise record the rendering limit.
   Treat Swift pseudocode as a design sketch, not compilation evidence.
6. Read the plan as a fresh executor without prior chat context.
   Find missing decisions, prerequisites, and ambiguous instructions that would force that executor to guess.
7. Correct supported findings and repeat the affected comparisons.
   Record new questions in the register and return them to the caller for [the question loop](#resolve-questions).
   Do not start a nested question loop during this review.
   Record the review date, source revision, reviewed scope, findings, dispositions, and remaining limits in Plan review.
   If no findings remain, say so without claiming that the implementation is verified.
8. Mark executable plans `ready` only when no unresolved question prevents their safe implementation or acceptance.
   Mark affected plans `blocked` when an external answer or feasibility result is required.
   Record the blocker and next action.
   Leave plans still being developed as `draft`.
   Preserve `executing` for unchanged work already in progress, and preserve valid `complete` or `superseded` records.
   Unaffected plans can be ready when their dependencies permit execution.

When called by another procedure, return the review result to that caller without publishing.
After initial plan development finishes, return to [Create a plan](../SKILL.md#create-a-plan) for publication and handoff.
