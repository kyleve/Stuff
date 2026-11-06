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

Return matched feedback and comment URLs to the calling workflow.
Use [Revise a plan](../SKILL.md#revise-a-plan) for authorized revisions and publication.
This reference owns comment retrieval and replies, not plan-editing mechanics.

## Close the loop

1. Verify that the calling workflow published the revisions before replying.
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
