# GitHub workflow: review replies

## Review comments

For feedback on `Plans/` files, also use [planning](../../planning/SKILL.md).
Its [GitHub review procedure](../../planning/references/github-review.md) covers plan revisions and dependent plans.
The addressing rules below also apply when the fix changes a plan rather than code.

Three modes:

**Exploring (user has not asked you to act):** read open review threads, summarize
what's there, and ask which to take on. Do not change code or post replies yet.

**Addressing (user pointed you at comments — e.g. "PTAL", "address review",
"fix the feedback"):** for each comment you fix in code, **also reply on GitHub**
in that thread. A code change without a reply is an incomplete handoff — the
reviewer cannot tell their note was seen.

**Historical audit (lessons or guidance changes):**

Use [review-lessons](../../review-lessons/SKILL.md) for historical evidence,
monthly audit windows, and guidance changes.
Use this skill for publishing the resulting PR.

When addressing:

- Read the complete thread, including later corrections, before deciding on a fix.
  Search for the same defect in sibling call sites and shared helpers.
  Keep product changes within the requested scope and file deferred occurrences.
- **One commit per review issue** — each distinct piece of feedback gets its
  own commit, unless several items fit together logically or address similar
  issues (then one commit for the group is fine). Either way, fixes stay
  bisectable.
- **Reply on every thread you fixed** — after pushing, reply naming the commit
  that resolved it (short summary of what changed). Use `gh` or
  `ManagePullRequest` `post_comment` with `in_reply_to` for review threads.
- **Reply on threads you declined** — say why, or that it was filed in the
  Stuff team's Linear backlog under [BACKLOG.md](../../../../BACKLOG.md). Never drop feedback silently.
- Anything deferred gets filed in Linear and the reply links
  to that item.
