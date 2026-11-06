# Apply a revision

This procedure owns plan edits for direct feedback, GitHub feedback, question answers, and findings during execution.
It returns updated plans and unresolved questions to its caller. It does not publish or start another question loop.

1. Read the current overview, affected plans, execution records, and relevant source.
   Identify the proposed change and its source, such as a request, comment URL, or question ID.
   If the change conflicts with user direction or expands scope, use existing authorization or return the missing decision.
   Keep unrelated work moving where dependencies permit it.
2. Determine which plans need revision, including dependent plans.
   For completed plans, apply the follow-up or reopening rule in the [Plans contract](../../../../Plans/AGENTS.md#structure-and-ownership).
   Preserve human edits, stable filenames, and story, requirement, exclusion, and question IDs.
3. Update affected stories, requirements, exclusions, decisions, diagrams, Swift sketches, steps, and verification together.
   If requirements or evidence change, revisit the affected discovery or research in [Develop an initial plan](develop-plan.md).
   Do not implement product changes during a plan-only revision.
4. Record the decision, reason, date, and source in the owning decision table.
   Put series-wide decisions in the overview and link them from affected plans.
   For a question answer, link its question record rather than duplicating the answer history.
   If a request is declined, record the reason.
   If work is deferred, link the owning `TODOs.md` item.
5. If the revision invalidates earlier verification, label that evidence stale and identify the checks that must repeat.
   Reset affected progress checkboxes and status to reflect remaining work.
   Preserve the earlier execution record.
   Treat material design revisions as `draft` until reviewed, or `blocked` when a required answer is missing.
6. Use [Review the plan](develop-plan.md#review-the-plan) to assess the revised series.
   During early discovery, review integration into existing sections and record unfinished drafting work without claiming full plan readiness.
   Return newly discovered questions to the caller instead of resolving them recursively.
   Report which changes were integrated and reviewed, declined, deferred, or still need an answer.
   Record unresolved decisions and their effect on execution.

The caller owns question status, the operation checkpoint, publication, and GitHub replies.
