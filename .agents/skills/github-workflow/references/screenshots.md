# GitHub workflow: screenshots

## Screen snapshot comments

For each new or changed screen, post a file-level PR review comment with a representative snapshot of the resulting screen.
These comments and their image updates are part of the screen-change handoff.

- Attach the comment to the screen's owning source file in the PR diff.
  If that file is unchanged, use the changed file responsible for the screen change.
  Name the screen in the comment.
- Before posting, look for an existing agent-authored snapshot comment for that screen.
  Maintain one snapshot comment per screen.
- Apply the capture, caption, revision, image-link, and publication checks from [Explain visible changes](pr-writing.md#explain-visible-changes).
  Include the [AI attribution](../SKILL.md#posting-under-the-users-identity) in the comment.
- With `gh api`, use the [review-comment API](https://docs.github.com/en/rest/pulls/comments) with `subject_type=file`, the source `path`, and the current head `commit_id`.
- After further screen-code changes, capture the updated screen.
  Edit the existing snapshot comment in place.
  Use its comment ID to update the body through the review-comment API.
  Replace the current image, caption, and capture revision.
  Preserve the discussion.
  Open the updated comment and check the image.
- If an image refresh is blocked, label the previous image as stale.
  Report the blocker.
