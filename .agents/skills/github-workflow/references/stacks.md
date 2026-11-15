# GitHub workflow: stacks

## Creating and maintaining stacked PRs

Treat a stack as one dependency chain even when the requested PR is near its
base. A conflict or failing integration in one slice can block every PR above
it.

- **Use `gh stack` for the whole stack lifecycle.** Never emulate a stack by
  manually chaining PR base branches with `gh pr create`, `gh pr edit`,
  `ManagePullRequest`, or raw pushes. Run `gh stack --version` first. If the
  extension is unavailable or reports that stacked PRs are not enabled for the
  repository, report the blocker instead of falling back to ordinary PRs.
- Create a new locally tracked stack before implementing its dependent slices.
  Pass branches bottom-to-top to `gh stack init --base <trunk> <branches...>`,
  or start the bottom branch with `gh stack init <branch>` and add each next
  layer from the current top with `gh stack add <branch>`. Put foundational
  work at the bottom and each dependent concern above it.
- Open or update every PR and the GitHub stack together with `gh stack submit
  --auto --open`. `--open` is required by this repo's ready-for-review rule.
  Without it, non-interactive submission creates drafts. After submission,
  use the ordinary per-PR editing tool to apply this skill's title/body guidance
  and template, then confirm the graph with `gh stack view --json`.
- Use `gh stack link --base <trunk> --open <bottom> ... <top>` only when the
  branches are managed without local `gh stack` tracking, such as
  by another branch tool or a separate worktree whose stack metadata is absent.
  Arguments are bottom-to-top. `link` pushes branches, creates or reuses PRs,
  corrects their bases, and links the remote stack. It does not create local
  navigation metadata.
- Start existing-stack work by checking it out with `gh stack checkout
  <stack-number-or-PR>` and inspecting the whole graph with `gh stack view
  --json`. Do not use bare `checkout`, `view`, `submit`, `switch`, or `modify`
  in an agent session because they can open an interactive picker or TUI. Then
  read every PR's base, head SHA, mergeability, merge-state status, and checks.
  Find the first broken slice. Do not assume the PR the user noticed owns the
  fault.
- Make a change on the earliest branch that owns it. After changing a lower
  slice, run `gh stack rebase --upstack` from that slice so every dependent
  branch inherits the fix, then use `gh stack push` to update the complete
  active chain. Use `gh stack sync` for the routine fetch/reconcile/rebase/push
  flow after trunk or remote stack state changes. It never opens missing PRs,
  so use `submit --auto --open` when the stack gains a new PR.
- Rebase from that first affected branch through the stack with `gh stack
  rebase --no-trunk --upstack`. This rewrites upstack branches, so obtain user
  authorization before doing it unless their request already explicitly covers
  repairing or updating the full stack.
- Resolve conflicts on the slice that introduced the affected code. Preserve
  both downstack fixes and the slice's intended addition. Do not accept one
  side wholesale merely to finish the rebase. Re-record snapshot references
  when both sides contain intentional visual changes.
- After each slice rebases, search it for logical conflicts such as references
  to renamed stylesheet tokens or APIs. Put the compatibility fix and its tests
  on the earliest slice that owns the affected code, commit it there, then
  continue rebasing the remaining upstack branches. Do not bury fixes for a
  lower PR in the stack head.
- Run focused behavior checks while repairing individual slices, then run the
  complete affected test and lint set at the stack tip. The tip contains every
  slice and is the final integration proof.
- Push the complete rewritten chain with `gh stack push`, then re-read every PR
  and verify its base branch, remote head SHA, and `mergeable` value. Return the
  checkout to the branch the user was reviewing when practical.
- Merge through `gh stack merge <stack-or-PR> --yes`, never `gh pr merge`.
  Passing a PR merges that PR plus every unmerged slice below it. Passing a
  stack number merges the whole stack. The operation is all-or-nothing unless
  the base uses a merge queue, in which case GitHub queues the selected stack.

`gh stack push` and `submit` are not atomic. Some branch or PR updates can land
before a later lease or API failure. Re-run after fixing the rejected slice and
verify every member. `gh stack sync` uses an atomic multi-branch push, restores
the stack if its cascade rebase conflicts, and can exit successfully after
aborting a non-interactive local/remote divergence. Read its final status rather
than trusting exit code alone. `gh stack <command> --help` is authoritative for
the installed extension's current flags and behavior.

GitHub commonly reports an otherwise mergeable upstack PR as `BLOCKED` while
its parent PR or required checks are pending. Distinguish that expected
downstack dependency from `CONFLICTING` / `DIRTY`, failed checks, or an
unexpected base before reporting the repair complete. Cancelled superseded
workflow runs immediately after a stacked force-push are also expected. Assess
the newest run for each head SHA.
