# Revise plans from GitHub feedback

If a plan has a linked PR or supplied GitHub feedback, use this reference.
Read [github-workflow](../../github-workflow/SKILL.md) for tools, publication, replies, and AI attribution.

## Read the feedback

1. Resolve the repository, PR, head commit, and plan paths from the supplied link or plan overview.
   Verify that the checkout contains the intended plan revision.
2. Fetch PR conversation comments, review summaries, and inline review threads with `gh`.
   `gh pr view --comments` alone is insufficient for inline review threads.
   Use paginated API requests for complete results.
   For GraphQL, paginate both the thread connection and each thread's comment connection.
3. Read complete relevant threads, including replies, corrections, and outdated comments.
   Include feedback on the overview and dependent plans.
   A resolved or outdated marker alone does not establish that the current plan incorporates the feedback.
4. Match inline comments by path, original revision, and quoted text.
   If lines moved, compare the original plan with the current file.
   Do not apply feedback using the current line number alone.
5. Compare feedback with recorded decisions and current source.
   Distinguish an unhandled request from one already addressed or withdrawn.

## Apply and record

When the user asks to revise from comments, update the plan files within that request.
When executing an already authorized plan, incorporate relevant feedback within the authorized scope.
If feedback conflicts with the user's direction or expands scope, record the conflict and request the missing decision.
Keep unrelated work moving where the dependency graph permits it.

For each substantive item:

- Apply the revision to affected stories, requirements, exclusions, diagrams, Swift sketches, steps, and dependent plans.
- If feedback changes a flow or interface, update its diagram, sketch, and acceptance criteria together.
- Record the comment URL, decision, and reason in the owning decision table.
- For questions or answers, update the question register through [the question loop](develop-plan.md#resolve-questions).
- If a request is declined, record the reason.
- If work is deferred, link its owning `TODOs.md` item.
- If evidence becomes stale, preserve it and identify the verification that must repeat.

Use [the planning revision procedure](../SKILL.md#revise-a-plan) for status and completion updates.
Preserve human edits and stable plan filenames.
Do not implement proposed product changes during a plan-only revision.

## Close the loop

1. Review the full revised series, then commit and push through github-workflow.
2. For authorized feedback work, reply on each addressed, declined, or deferred thread.
   Include the revision commit and relevant plan path.
   For a conversation comment, identify its permalink in the reply.
   Group related conversation replies to avoid duplicate posts.
3. Before posting, inspect existing replies for that comment and revision.
   If a matching reply exists, avoid posting it again.
4. If requested, resolve review threads as specified by github-workflow.
5. Refresh feedback once before handoff and handle new relevant comments within scope.
   Record the PR head and feedback-read time in the execution record or revision entry.
   If feedback keeps arriving, report the remaining comments rather than waiting indefinitely.

This workflow reads comments when invoked. It does not install a GitHub listener or watch for future comments.
